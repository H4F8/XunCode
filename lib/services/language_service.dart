import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:flutter/widgets.dart';

import 'file_service.dart';
import 'settings_service.dart';

/// Описание одного доступного языка — встроенного или пользовательского.
class LanguageEntry {
  /// Уникальный код языка, обычно совпадает с именем файла без `.txt`.
  /// Для встроенных языков соответствует ISO-коду (`ru`, `en`).
  final String code;

  /// Отображаемое имя из ключа `_meta.name` в файле, либо сам код.
  final String displayName;

  /// Путь к файлу. Для встроенных языков указывает на копию в
  /// `Languages/`, куда они выложены при первом запуске.
  final String path;

  /// True, если этот язык поставляется вместе с приложением.
  final bool builtin;

  const LanguageEntry({
    required this.code,
    required this.displayName,
    required this.path,
    required this.builtin,
  });
}

/// Сервис локализации UI XunCode на основе .txt файлов.
///
/// Файлы `assets/languages/*.txt` копируются на первом запуске в
/// `<sharedRoot>/Languages/`, после чего любая программа (или пользователь)
/// может добавить туда свой `.txt` с парами `key=value`.
///
/// Активный язык хранится в SharedPreferences под ключом `language`.
/// Значение `'system'` означает «следовать системному языку».
class LanguageService extends ChangeNotifier {
  static const _bundledLanguages = ['ru', 'en'];
  static const _builtinDisplay = {
    'ru': 'Русский',
    'en': 'English',
  };

  final SettingsService _settings;

  String _code = 'system';
  Locale _locale = const Locale('ru');
  Map<String, String> _strings = const {};
  Map<String, String> _fallback = const {};
  List<LanguageEntry> _available = const [];

  LanguageService(this._settings);

  String get code => _code;
  Locale get locale => _locale;
  List<LanguageEntry> get available => List.unmodifiable(_available);

  /// Доступ из дерева виджетов. Возвращает уже зарегистрированный экземпляр
  /// через Provider; чтобы перерисовка происходила при смене языка, виджет
  /// должен подписаться через `Provider.of<LanguageService>(ctx)`.
  static LanguageService of(BuildContext ctx, {bool listen = true}) =>
      Provider.of<LanguageService>(ctx, listen: listen);

  Future<void> init() async {
    await _ensureBundleCopied();
    await _scan();
    _code = _settings.language;
    await _loadActive();
  }

  /// Перенести встроенные `.txt` из bundle в shared `Languages/`.
  /// Делаем это только при первом запуске или при смене версии (мы пишем
  /// маркер `_bundle_v` в SharedPreferences). Каждый старт без проверки
  /// блокировал бы UI на 50–200 мс на типичном устройстве.
  Future<void> _ensureBundleCopied() async {
    await FileService.ensureLayout();
    final dir = Directory(FileService.languagesDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    const bundleVersion = '6';
    final marker = _settings.bundleVersion;
    final allBuiltinPresent = await _bundledLanguagesPresent(dir);
    if (marker == bundleVersion && allBuiltinPresent) return;

    for (final code in _bundledLanguages) {
      try {
        final asset = 'assets/languages/$code.txt';
        final data = await rootBundle.loadString(asset);
        final f = File('${dir.path}/$code.txt');
        await f.writeAsString(data, flush: true);
      } catch (_) {
        // Если ассет не упакован или нет доступа на запись — молча
        // пропускаем. Tr() позже всё равно фолбэкнет на bundle через rootBundle.
      }
    }
    await _settings.setBundleVersion(bundleVersion);
  }

  Future<bool> _bundledLanguagesPresent(Directory dir) async {
    for (final code in _bundledLanguages) {
      if (!await File('${dir.path}/$code.txt').exists()) return false;
    }
    return true;
  }

  Future<void> _scan() async {
    final entries = <LanguageEntry>[];
    final seen = <String>{};
    try {
      final dir = Directory(FileService.languagesDir);
      if (await dir.exists()) {
        final files = await dir
            .list(followLinks: false)
            .where((e) => e is File && e.path.toLowerCase().endsWith('.txt'))
            .cast<File>()
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          final code = _codeFromPath(f.path);
          if (code.isEmpty || seen.contains(code)) continue;
          seen.add(code);
          final meta = await _readMeta(f);
          entries.add(LanguageEntry(
            code: code,
            displayName: meta['_meta.name'] ?? _builtinDisplay[code] ?? code,
            path: f.path,
            builtin: _bundledLanguages.contains(code),
          ));
        }
      }
    } catch (_) {}
    // Гарантируем встроенные языки даже если sharedRoot недоступен.
    for (final code in _bundledLanguages) {
      if (seen.contains(code)) continue;
      entries.add(LanguageEntry(
        code: code,
        displayName: _builtinDisplay[code] ?? code,
        path: 'asset:assets/languages/$code.txt',
        builtin: true,
      ));
    }
    entries.sort((a, b) {
      // Встроенные сверху, потом по алфавиту.
      if (a.builtin && !b.builtin) return -1;
      if (!a.builtin && b.builtin) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    _available = entries;
  }

  Future<void> _loadActive() async {
    _fallback = await _readDictionary('en');
    final resolved = _resolveCode(_code);
    _strings = resolved == 'en' ? _fallback : await _readDictionary(resolved);
    _locale = Locale(resolved);
  }

  String _resolveCode(String requested) {
    if (requested != 'system') {
      if (_available.any((e) => e.code == requested)) return requested;
    }
    final sys = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (_available.any((e) => e.code == sys)) return sys;
    return 'ru';
  }

  Future<Map<String, String>> _readDictionary(String code) async {
    final entry = _available.firstWhere(
      (e) => e.code == code,
      orElse: () => LanguageEntry(
        code: code,
        displayName: code,
        path: 'asset:assets/languages/$code.txt',
        builtin: _bundledLanguages.contains(code),
      ),
    );
    String? raw;
    if (entry.path.startsWith('asset:')) {
      try {
        raw = await rootBundle.loadString(entry.path.substring('asset:'.length));
      } catch (_) {}
    } else {
      try {
        final f = File(entry.path);
        if (await f.exists()) raw = await f.readAsString();
      } catch (_) {}
    }
    if (raw == null && code != 'en') {
      // последний шанс — встроенный английский
      try {
        raw = await rootBundle.loadString('assets/languages/en.txt');
      } catch (_) {}
    }
    return _parse(raw ?? '');
  }

  /// Прочитать только секцию с `_meta.*` ключами без полного парсинга,
  /// чтобы скан папки был дешёвым.
  Future<Map<String, String>> _readMeta(File f) async {
    try {
      final stream = f.openRead().transform(const _Utf8LineSplitter());
      final out = <String, String>{};
      await for (final line in stream) {
        if (!line.startsWith('_meta.')) continue;
        final eq = line.indexOf('=');
        if (eq < 0) continue;
        out[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Map<String, String> _parse(String raw) {
    final out = <String, String>{};
    for (final rawLine in raw.split('\n')) {
      var line = rawLine.replaceAll('\r', '').trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim().replaceAll(r'\n', '\n');
      if (key.isEmpty) continue;
      out[key] = value;
    }
    return out;
  }

  String _codeFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  /// Сменить активный язык. `code` может быть `'system'`, кодом встроенного
  /// языка или именем кастомного `.txt` без расширения.
  Future<void> setLanguage(String code) async {
    _code = code;
    await _settings.set('language', code);
    await _loadActive();
    notifyListeners();
  }

  /// Перечитать список языков из shared-папки. Используется кнопкой
  /// «Refresh» в настройках, чтобы пользователь мог увидеть только что
  /// положенный туда `.txt`.
  Future<void> refresh() async {
    await _scan();
    await _loadActive();
    notifyListeners();
  }

  /// Базовый translate. Подставляет именованные плейсхолдеры вида `{name}`
  /// из `params`. Если ключ не найден — возвращает сам ключ, чтобы пропавшая
  /// строка сразу бросалась в глаза.
  String tr(String key, {Map<String, Object?>? params, String? fallback}) {
    var value = _strings[key] ?? _fallback[key] ?? fallback ?? key;
    if (params != null && params.isNotEmpty) {
      params.forEach((k, v) {
        value = value.replaceAll('{$k}', v?.toString() ?? '');
      });
    }
    return value;
  }
}

/// Декодирует UTF-8 поток построчно, не загружая весь файл в память.
class _Utf8LineSplitter extends StreamTransformerBase<List<int>, String> {
  const _Utf8LineSplitter();

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    final buf = StringBuffer();
    await for (final chunk in stream) {
      final s = String.fromCharCodes(chunk);
      for (final ch in s.split('')) {
        if (ch == '\n') {
          yield buf.toString().replaceAll('\r', '').trim();
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) yield tail;
  }
}
