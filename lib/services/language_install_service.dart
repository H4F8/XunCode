import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language.dart';
import 'file_service.dart';

typedef ProgressCb = void Function(double progress, String stage);

/// Скачивает / удаляет / перечисляет среды программирования.
///
/// Хранит:
///  • Бинарники / распакованные тулчейны:
///    `<privateRoot>/languages/<id>/`
///  • JSON-список пользовательских языков в SharedPreferences под ключом
///    `languages.custom`.
///  • Маркер `installed.json` внутри папки языка с реальной версией и URL,
///    из которого был установлен.
class LanguageInstallService extends ChangeNotifier {
  LanguageInstallService._();
  static final LanguageInstallService instance = LanguageInstallService._();

  static const _customKey = 'languages.custom';
  static const _registryOverrideKey = 'languages.registryOverride';

  List<Language> _custom = const [];
  Map<String, String> _registryOverride = const {};
  bool _loaded = false;

  /// Все известные языки: встроенные + пользовательские. Дубликаты по `id`
  /// исключаются — пользовательский с тем же id перебивает встроенный.
  List<Language> get allKnown {
    final byId = <String, Language>{};
    for (final b in builtinLanguages) {
      byId[b.id] = b;
    }
    for (final c in _custom) {
      byId[c.id] = c;
    }
    return byId.values.toList();
  }

  List<Language> get builtin => List.unmodifiable(builtinLanguages);
  List<Language> get custom => List.unmodifiable(_custom);

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _custom = Language.decodeList(prefs.getString(_customKey) ?? '');
    final raw = prefs.getString(_registryOverrideKey) ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _registryOverride = decoded.map(
              (k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  // ── Custom language CRUD ──────────────────────────────────────────────

  Future<void> addCustom(Language lang) async {
    final filtered = _custom.where((l) => l.id != lang.id).toList()
      ..add(lang.copyWith(builtin: false));
    _custom = filtered;
    await _persistCustom();
    notifyListeners();
  }

  Future<void> removeCustom(String id) async {
    _custom = _custom.where((l) => l.id != id).toList();
    await _persistCustom();
    await _deleteInstallDir(id);
    notifyListeners();
  }

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customKey, Language.encodeList(_custom));
  }

  // ── Install / uninstall ──────────────────────────────────────────────

  bool isInstalledSync(String id) {
    return File('${FileService.languagesInstallDir}/$id/installed.json')
        .existsSync();
  }

  Future<bool> isInstalled(String id) async {
    return File('${FileService.languagesInstallDir}/$id/installed.json')
        .exists();
  }

  String installPathOf(String id) =>
      '${FileService.languagesInstallDir}/$id';

  /// Скачивает архив языка и распаковывает в `<privateRoot>/languages/<id>/`.
  /// Поддерживает `.tar.gz` / `.tgz`, `.tar.xz`, `.tar`, `.zip`. Идемпотентно:
  /// если уже установлен — возвращает true сразу.
  Future<bool> install(Language lang, {ProgressCb? onProgress}) async {
    final dir = Directory(installPathOf(lang.id));
    if (await isInstalled(lang.id)) return true;
    await FileService.ensureLayout();
    await Directory(FileService.languagesInstallDir).create(recursive: true);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final archivePath = '${FileService.tmpDir}/${lang.id}.archive';
    await _silent(() => File(archivePath).delete());

    onProgress?.call(0, 'Resolving');
    final dio = Dio();
    try {
      await dio.download(
        lang.url,
        archivePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total, 'Downloading');
          }
        },
      );
    } catch (e) {
      await _silent(() => File(archivePath).delete());
      throw 'Download failed: $e';
    }

    onProgress?.call(0, 'Extracting');
    try {
      // Распаковка — самая дорогая операция (CPU + IO). Гоним её через
      // compute() в отдельном изоляте, чтобы UI-поток оставался свободным.
      // Таймаут 15 минут: rust/jdk тянутся и распаковываются на телефоне
      // по несколько минут, прежние 120 с рвали установку на середине.
      await compute(_extractInIsolate, <String, String>{
        'archivePath': archivePath,
        'outDir': dir.path,
        'tmpDir': FileService.tmpDir,
      }).timeout(const Duration(seconds: 900),
          onTimeout: () => throw 'Extraction timed out (>15 min)');
      onProgress?.call(1.0, 'Extracting');

      // Защита от «тихих» неудач: пустой результат = ошибка.
      final hasFiles =
          dir.existsSync() && dir.listSync(recursive: true).isNotEmpty;
      if (!hasFiles) throw 'Extraction produced no files';
    } catch (e) {
      await _silent(() => dir.delete(recursive: true));
      throw 'Extraction failed: $e';
    } finally {
      await _silent(() => File(archivePath).delete());
    }

    final marker = File('${dir.path}/installed.json');
    await marker.writeAsString(jsonEncode(lang.toJson()));
    onProgress?.call(1.0, 'Done');
    notifyListeners();
    return true;
  }

  Future<void> uninstall(String id) async {
    await _deleteInstallDir(id);
    notifyListeners();
  }

  Future<void> _deleteInstallDir(String id) async {
    final dir = Directory(installPathOf(id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ── Registry override ────────────────────────────────────────────────

  /// Эффективный URL реестра для языка с учётом пользовательского override'а.
  String? registryFor(Language lang) =>
      _registryOverride[lang.id] ?? lang.registry;

  Future<void> setRegistryOverride(String id, String? url) async {
    final next = Map<String, String>.from(_registryOverride);
    if (url == null || url.isEmpty) {
      next.remove(id);
    } else {
      next[id] = url;
    }
    _registryOverride = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registryOverrideKey, jsonEncode(next));
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Future<void> _silent(Future<Object?> Function() block) async {
    try {
      await block();
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _custom = const [];
    _registryOverride = const {};
    _loaded = false;
  }
}

/// Точка входа для compute(). Выполняется в отдельном изоляте, поэтому не
/// имеет доступа ни к UI, ни к статикам Flutter — только чистая работа с
/// файлами. Возвращает `'ok'` или бросает исключение со строковым описанием.
String _extractInIsolate(Map<String, String> args) {
  final archivePath = args['archivePath']!;
  final outDir = args['outDir']!;
  final tmpDir = args['tmpDir']!;
  final lower = archivePath.toLowerCase();

  // Основной путь — системный tar (toybox на Android, GNU tar на desktop):
  // стримит с диска, сохраняет симлинки и права исполнения и не грузит
  // распакованное содержимое в память. Прежний вариант через decodeBuffer()
  // держал весь распакованный tar в ОЗУ — rust (~1.3 ГБ) или jdk убивался
  // Android'ом по OOM, и установка «молча» не доходила до конца.
  final viaTar = _trySystemTar(archivePath, outDir, lower);
  if (viaTar != null) return viaTar;

  Archive archive;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz') ||
      lower.endsWith('.archive')) {
    final input = InputFileStream(archivePath);
    final tarPath = '$tmpDir/${_basenameOf(archivePath)}.tar';
    try {
      final out = OutputFileStream(tarPath);
      try {
        GZipDecoder().decodeStream(input, out);
      } finally {
        out.closeSync();
      }
      final tarStream = InputFileStream(tarPath);
      try {
        archive = TarDecoder().decodeBuffer(tarStream);
        _writeArchiveSync(archive, outDir);
      } finally {
        tarStream.closeSync();
      }
      try { File(tarPath).deleteSync(); } catch (_) {}
      return 'ok';
    } catch (_) {
      try { File(tarPath).deleteSync(); } catch (_) {}
      // Не gzip — пробуем дальше.
    } finally {
      input.closeSync();
    }
  }
  if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    // archive 3.6.x: XZDecoder работает только с byte-buffers.
    final bytes = File(archivePath).readAsBytesSync();
    final decodedBytes = XZDecoder().decodeBytes(bytes);
    archive = TarDecoder().decodeBytes(decodedBytes);
    _writeArchiveSync(archive, outDir);
    return 'ok';
  }
  final input = InputFileStream(archivePath);
  try {
    if (lower.endsWith('.tar')) {
      archive = TarDecoder().decodeBuffer(input);
      _writeArchiveSync(archive, outDir);
      return 'ok';
    }
    if (lower.endsWith('.zip') || lower.endsWith('.archive')) {
      archive = ZipDecoder().decodeBuffer(input);
      _writeArchiveSync(archive, outDir);
      return 'ok';
    }
    throw 'Unsupported archive format: $archivePath';
  } finally {
    input.closeSync();
  }
}

/// Пытается распаковать системным tar. Возвращает 'ok' при успехе,
/// null — если tar недоступен или не справился (тогда fallback на Dart).
String? _trySystemTar(String archivePath, String outDir, String lower) {
  String flags;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    flags = '-xzf';
  } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    flags = '-xJf'; // на Android xz обычно нет — уйдём в fallback
  } else if (lower.endsWith('.tar')) {
    flags = '-xf';
  } else {
    return null; // формат не для tar — сразу fallback (zip)
  }
  try {
    final res = Process.runSync('tar', [flags, archivePath, '-C', outDir]);
    if (res.exitCode == 0 &&
        Directory(outDir).existsSync() &&
        Directory(outDir).listSync().isNotEmpty) {
      return 'ok';
    }
  } catch (_) {}
  return null;
}

void _writeArchiveSync(Archive archive, String outDir) {
  final executables = <String>[];
  final links = <MapEntry<String, String>>[];
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    if (name.startsWith('/') || name.contains('../')) continue;
    final outPath = '$outDir/$name';
    if (entry.isSymbolicLink) {
      links.add(MapEntry(outPath, entry.nameOfLinkedFile));
      continue;
    }
    if (entry.isFile) {
      final f = File(outPath);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(entry.content as List<int>, flush: false);
      if ((entry.mode & 0o100) != 0) executables.add(outPath);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
  // Симлинки: dart:io Link работает и на Android (обычный syscall).
  for (final l in links) {
    try {
      final existing = File(l.key);
      if (existing.existsSync()) existing.deleteSync();
      Link(l.key).createSync(l.value);
    } catch (_) {}
  }
  // Права исполнения: без них bin/java, bin/go и т.п. не запускаются.
  for (var i = 0; i < executables.length; i += 400) {
    final chunk = executables.skip(i).take(400).toList();
    try {
      Process.runSync('chmod', ['755', ...chunk]);
    } catch (_) {}
  }
}

String _basenameOf(String p) => p.split(Platform.pathSeparator).last;
