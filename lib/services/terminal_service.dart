import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';

const _kEmbeddedRootfsAsset = 'assets/rootfs/';

/// Платформо-зависимый терминальный мост.
///
/// На Android используется AXS (Acode eXecution Server) + proot + Alpine Linux
/// для обхода noexec/W^X на Android 13+. AXS стартует как отдельный процесс
/// и принимает WebSocket-подключения, через которые идёт ввод/вывод.
///
/// На Linux/macOS/Windows (desktop) AXS не нужен — терминальная сессия
/// запускается как обычный дочерний процесс через [Process.start], а ввод и
/// вывод идут напрямую через stdin/stdout. Это упрощает код и избавляет от
/// необходимости тянуть Alpine rootfs.
class TerminalBridge {
  static const _method = MethodChannel('com.xunkal1.xuncode/terminal');
  static const _events = EventChannel('com.xunkal1.xuncode/terminal/events');

  static int? _axsPort;
  static Process? _axsProcess;
  static final Map<String, _BackendSession> _sockets = {};
  static const _axsTimeout = Duration(seconds: 10);

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  // ── AXS binary management (Android only) ───────────────────────────

  static Future<File> _axsBinary() async {
    if (_isDesktop) {
      throw UnsupportedError('AXS is Android-only');
    }
    final native = await _axsBinaryFromNativeLib();
    if (native != null) return native;

    // В APK бинарники движка кладутся только в jniLibs/arm64-v8a.
    // Если их нет в nativeLibraryDir — почти наверняка 32-битное
    // устройство (armeabi-v7a), где терминальный движок недоступен:
    // честно сообщаем об этом вместо тихого Permission denied.
    final abi = _abi();
    if (abi != 'arm64-v8a') {
      throw UnsupportedError(
          'Terminal engine binaries are arm64-only, device ABI is $abi');
    }

    // Фолбэк на asset — работает только там, где exec из data разрешён
    // (Android < 10). На новых версиях это последний шанс с явной ошибкой.
    final dir = await getApplicationSupportDirectory();
    final axsDir = Directory('${dir.path}/axs');
    final axsFile = File('${axsDir.path}/axs');
    if (await axsFile.exists()) return axsFile;

    await axsDir.create(recursive: true);
    final byteData = await rootBundle.load('assets/axs/axs');
    await axsFile.writeAsBytes(byteData.buffer.asUint8List());
    // Без +x Process.start упадёт с Permission denied. dart:io не умеет
    // chmod, поэтому зовём системный chmod (toybox есть на всех Android).
    try {
      await Process.run('chmod', ['755', axsFile.path]);
    } catch (_) {}
    return axsFile;
  }

  static Future<File?> _axsBinaryFromNativeLib() async {
    try {
      final nativeDir =
          await _method.invokeMethod<String>('getNativeLibraryDir') ??
              '/data/app/com.xunkal1.xuncode/lib/arm64';
      final file = File('$nativeDir/libaxs.so');
      if (await file.exists() && await file.length() > 0) return file;
    } catch (_) {}
    return null;
  }

  /// Полная команда для старта Alpine внутри proot. Сервер исполнения
  /// сплитит её по пробелам: первый токен — программа, остальное — аргументы.
  static String _prootCommand(String nativeDir, String rootfs) {
    final proot = '$nativeDir/libproot.so';
    return [
      proot,
      '-r', rootfs,
      '-w', '/home/user',
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      '-b', '/dev/urandom:/dev/random',
      '-b', '/proc/self/fd:/dev/fd',
      '-b', '/sdcard',
      '/bin/sh', '-l',
    ].join(' ');
  }

  static Future<void> _ensureAxs() async {
    if (_isDesktop) return; // no AXS on desktop
    // Упавший движок перезапускаем автоматически.
    if (_axsProcess != null) {
      final alive = await _processAlive(_axsProcess);
      if (alive) return;
      _axsProcess = null;
      _axsPort = null;
    }
    final axs = await _axsBinary();
    final nativeDir =
        await _method.invokeMethod<String>('getNativeLibraryDir') ?? '';
    final rootfs = await rootfsPath();

    // proot распаковывает свой загрузчик во временный каталог: без
    // доступного PROOT_TMP_DIR он умирает мгновенно на Android.
    final tmpRoot = Directory(FileService.tmpDir);
    if (!await tmpRoot.exists()) await tmpRoot.create(recursive: true);
    final prootTmp = Directory('${tmpRoot.path}/proot-tmp');
    if (!await prootTmp.exists()) await prootTmp.create(recursive: true);

    // ВАЖНО: environment в dart:io ПОЛНОСТЬЮ заменяет окружение —
    // наследуем родительское, иначе дочерние процессы остаются без PATH.
    _axsProcess = await Process.start(axs.path, [
      '-p', '0',
      '-c', _prootCommand(nativeDir, rootfs),
    ], environment: {
      ...Platform.environment,
      'LD_LIBRARY_PATH': nativeDir,
      'PROOT_TMP_DIR': prootTmp.path,
      'TMPDIR': prootTmp.path,
      'HOME': tmpRoot.path,
    });

    // Сервер логирует «listening on 127.0.0.1:PORT» (ранние сборки писали
    // «started on http://…»). ANSI-коды срезаем на всякий случай.
    final portRe = RegExp(
      r'(?:listening\s+on|started\s+on)\s+(?:http://)?[\w.\-]+:(\d+)',
    );
    final stdoutDone = Completer<int?>();
    final stderrFirst = Completer<String>();
    late StreamSubscription subOut;
    late StreamSubscription subErr;

    void failStart(Object e) {
      if (!stdoutDone.isCompleted) stdoutDone.completeError(e);
    }

    subOut = _axsProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (raw) {
        final line = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
        final m = portRe.firstMatch(line);
        if (m != null && !stdoutDone.isCompleted) {
          stdoutDone.complete(int.tryParse(m.group(1)!));
          subOut.cancel();
        }
      },
      onError: failStart,
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete(null);
      },
    );

    subErr = _axsProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (!stderrFirst.isCompleted && line.trim().isNotEmpty) {
          stderrFirst.complete(line);
        }
      },
      onError: (Object e) {
        if (!stderrFirst.isCompleted) stderrFirst.complete('');
      },
      onDone: () {
        if (!stderrFirst.isCompleted) stderrFirst.complete('');
      },
    );

    int? port;
    try {
      port = await Future.any([
        stdoutDone.future,
        Future.delayed(_axsTimeout, () => throw TimeoutException('AXS start timeout')),
      ]);
    } catch (e) {
      subOut.cancel();
      subErr.cancel();
      _killAxs();
      throw Exception('AXS failed to start: $e');
    }

    if (port == null || port <= 0) {
      final err =
          stderrFirst.isCompleted ? await stderrFirst.future : '';
      subOut.cancel();
      subErr.cancel();
      _killAxs();
      throw Exception(
          'AXS did not report a port${err.isNotEmpty ? ": $err" : ""}');
    }
    _axsPort = port;
  }

  static void _killAxs() {
    _axsProcess?.kill();
    _axsProcess = null;
    _axsPort = null;
  }

  static Future<bool> _processAlive(Process? p) async {
    if (p == null) return false;
    try {
      await p.exitCode.timeout(const Duration(milliseconds: 1));
      return false; // уже завершился
    } on TimeoutException {
      return true;
    }
  }

  /// Разовое выполнение команды внутри Alpine (эндпоинт /execute-command).
  /// Возвращает вывод команды. Работает только при поднятом движке.
  static Future<String?> execCommand(String command, {String? cwd}) async {
    if (_isDesktop) return null;
    await _ensureAxs();
    final port = _axsPort;
    if (port == null) return null;
    try {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:$port/execute-command'),
        body: jsonEncode({'command': command, 'cwd': cwd ?? ''}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }

  /// Создаёт PTY-сессию на сервере: POST /terminals → текстовый pid.
  static Future<String> _createAxsSession(int port, int cols, int rows) async {
    final res = await http.post(
      Uri.parse('http://127.0.0.1:$port/terminals'),
      body: jsonEncode({'cols': cols.toString(), 'rows': rows.toString()}),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Failed to create terminal session (${res.statusCode})');
    }
    final pid = res.body.trim().replaceAll('"', '');
    if (pid.isEmpty) throw Exception('Server returned empty session id');
    return pid;
  }

  /// Путь к rootfs Alpine
  static Future<String> rootfsPath() async {
    if (_isDesktop) {
      // На desktop мы не используем proot-rootfs, но возвращаем путь к
      // пользовательской директории для совместимости.
      final dir = await getApplicationSupportDirectory();
      final rootfs = Directory('${dir.path}/rootfs');
      if (!await rootfs.exists()) await rootfs.create(recursive: true);
      return rootfs.path;
    }
    return await _method.invokeMethod<String>('rootfsPath') ?? '';
  }

  // ── Alpine rootfs (Android only — на desktop без proot) ───────────

  static Future<bool> isAlpineInstalled() async {
    if (_isDesktop) {
      // На desktop всегда «установлено» — используется системный shell.
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('alpine.installed') == true) {
      try {
        final root = await rootfsPath();
        if (root.isNotEmpty && await _rootfsHealthy(root)) {
          final marker = File('$root/.installed');
          if (!await marker.exists()) {
            await marker.writeAsString('ok');
          }
          return true;
        }
      } catch (_) {}
      // Маркер есть, но rootfs бит (наследие старого распаковщика) —
      // сбрасываем и переустанавливаем при следующем запуске.
      await prefs.setBool('alpine.installed', false);
    }
    final v = await _method.invokeMethod<bool>('isAlpineInstalled');
    final installed = v ?? false;
    if (installed) await prefs.setBool('alpine.installed', true);
    return installed;
  }

  static Future<void> clearAlpineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alpine.installed', false);
    if (_isDesktop) return;
    try {
      final root = await rootfsPath();
      if (root.isNotEmpty) {
        final dir = Directory(root);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {}
    try {
      await _method.invokeMethod('clearRootfs');
    } catch (_) {}
  }

  static Future<void> markAlpineInstalled() async {
    if (_isDesktop) return;
    await _method.invokeMethod('markAlpineInstalled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alpine.installed', true);
  }

  /// Возвращает true, если в assets встроен rootfs.
  static Future<bool> hasEmbeddedRootfs() async {
    try {
      final manifest = await rootBundle.loadString('$_kEmbeddedRootfsAsset/manifest.json');
      final json = jsonDecode(manifest) as Map<String, dynamic>;
      return json['arch']?.toString().isNotEmpty ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Распаковывает встроенный в assets rootfs в рабочую директорию приложения.
  /// Проверка здоровья rootfs: busybox существует как файл, /bin/sh
  /// существует и НЕ является директорией. Старые версии распаковщика
  /// превращали симлинк /bin/sh → /bin/busybox в пустую папку, из-за
  /// чего proot мгновенно падал.
  static Future<bool> _rootfsHealthy(String root) async {
    if (!await File('$root/bin/busybox').exists()) return false;
    if (await Directory('$root/bin/sh').exists()) return false;
    return await File('$root/bin/sh').exists();
  }

  static Future<void> _wipeRootfs(String root) async {
    final d = Directory(root);
    if (await d.exists()) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
    await d.create(recursive: true);
  }

  /// Распаковка системным tar — сохраняет симлинки и права «как есть».
  static Future<bool> _trySystemTarRootfs(String gzPath, String dest) async {
    for (final flags in const ['-xzf', '-xf']) {
      try {
        final r = await Process.run('tar', [flags, gzPath, '-C', dest]);
        if (r.exitCode == 0) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Чисто-Dart фолбэк: настоящие симлинки (dart:io Link работает на
  /// Android), batched chmod для исполнимых файлов. Архитектурно повторяет
  /// экстрактор языковых пакетов.
  static Future<void> _extractTarEntries(
    String tarPath,
    String root,
    void Function(double progress, String stage)? onProgress,
  ) async {
    final stream = InputFileStream(tarPath);
    final execPaths = <String>[];
    try {
      final archive = TarDecoder().decodeBuffer(stream);
      final total = archive.length.clamp(1, 1 << 30);
      var done = 0;
      for (final entry in archive) {
        final outPath = '$root/${entry.name}';
        if (entry.isFile) {
          final f = File(outPath);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(entry.content as List<int>, flush: false);
          // 0x40 = owner-exec в правах tar.
          if ((entry.mode & 0x40) != 0) execPaths.add(outPath);
        } else if (entry.isSymbolicLink) {
          try {
            await Link(outPath).create(entry.nameOfLinkedFile);
          } catch (_) {}
        } else {
          await Directory(outPath).create(recursive: true);
        }
        done++;
        if (done % 200 == 0) onProgress?.call(done / total, 'Extracting Alpine');
      }
    } finally {
      await stream.close();
    }
    // dart:io не умеет chmod — пакетные вызовы системного chmod
    // (по 400 путей за вызов, чтобы не превысить ARG_MAX).
    for (var i = 0; i < execPaths.length; i += 400) {
      final end = (i + 400).clamp(0, execPaths.length);
      try {
        await Process.run('chmod', ['755', ...execPaths.sublist(i, end)]);
      } catch (_) {}
    }
  }

  static Future<void> extractEmbeddedRootfs(
    void Function(double progress, String stage)? onProgress,
  ) async {
    if (_isDesktop) return;
    final root = await rootfsPath();

    // Здоровый rootfs не трогаем; битый/недораспакованный от прошлых
    // версий — сносим и ставим заново (самозалечка при обновлении).
    if (await _rootfsHealthy(root)) {
      await markAlpineInstalled();
      return;
    }

    onProgress?.call(0.05, 'Extracting Alpine');
    await _wipeRootfs(root);

    final bytes = await rootBundle.load('$_kEmbeddedRootfsAsset/rootfs.tar.gz');
    final tmpRoot = Directory(FileService.tmpDir);
    if (!await tmpRoot.exists()) await tmpRoot.create(recursive: true);
    final gzPath = '${tmpRoot.path}/embedded-rootfs.tar.gz';
    final tarPath = '${tmpRoot.path}/embedded-rootfs.tar';
    await File(gzPath).writeAsBytes(bytes.buffer.asUint8List());

    final input = InputFileStream(gzPath);
    final output = OutputFileStream(tarPath);
    try {
      GZipDecoder().decodeStream(input, output);
    } finally {
      await input.close();
      await output.close();
    }

    onProgress?.call(0.15, 'Extracting Alpine');
    if (!await _trySystemTarRootfs(gzPath, root)) {
      await _extractTarEntries(tarPath, root, onProgress);
    }

    await _silent(() => File(gzPath).delete());
    await _silent(() => File(tarPath).delete());

    if (!await _rootfsHealthy(root)) {
      throw StateError(
          'Rootfs extraction failed verification (/bin/sh or /bin/busybox missing)');
    }
    onProgress?.call(1.0, 'Extracting Alpine');
    await markAlpineInstalled();
  }

  /// Установка Alpine: сначала пробуем встроенный tar.gz, иначе качаем из сети.
  static Future<void> installAlpine({
    void Function(double progress, String stage)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (_isDesktop) {
      onProgress?.call(1.0, 'Desktop — uses system shell');
      await markAlpineInstalled();
      return;
    }
    if (await isAlpineInstalled()) return;

    if (await hasEmbeddedRootfs()) {
      await extractEmbeddedRootfs(onProgress);
      return;
    }

    await _downloadAndExtractRootfs(onProgress, cancelToken);
  }

  /// Скачивает Alpine minirootfs из интернета (fallback).
  static Future<void> _downloadAndExtractRootfs(
    void Function(double progress, String stage)? onProgress,
    CancelToken? cancelToken,
  ) async {
    final root = await rootfsPath();
    final rootDir = Directory(root);
    if (!await rootDir.exists()) await rootDir.create(recursive: true);

    final arch = _alpineArch();
    final url = 'https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$arch/'
        'alpine-minirootfs-3.20.3-$arch.tar.gz';

    await FileService.ensureLayout();
    final tmpRoot = Directory(FileService.tmpDir);
    if (!await tmpRoot.exists()) await tmpRoot.create(recursive: true);
    final gzPath = '${tmpRoot.path}/alpine-minirootfs.tar.gz';
    final tarPath = '${tmpRoot.path}/alpine-minirootfs.tar';

    await _silent(() => File(gzPath).delete());
    await _silent(() => File(tarPath).delete());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rootfs_downloading', true);

    Future<void> cleanupPartial() async {
      await _silent(() => File(gzPath).delete());
      await _silent(() => File(tarPath).delete());
      try {
        if (await rootDir.exists()) {
          await rootDir.delete(recursive: true);
        }
      } catch (_) {}
      await prefs.setBool('rootfs_downloading', false);
      await prefs.setBool('alpine.installed', false);
    }

    try {
      final dio = Dio();
      await dio.download(
        url,
        gzPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total, 'Downloading Alpine');
          }
        },
      );

      onProgress?.call(0.0, 'Decompressing');
      final input = InputFileStream(gzPath);
      final output = OutputFileStream(tarPath);
      try {
        GZipDecoder().decodeStream(input, output);
      } finally {
        await input.close();
        await output.close();
      }

      onProgress?.call(0.15, 'Extracting');
      if (!await _trySystemTarRootfs(gzPath, root)) {
        await _extractTarEntries(tarPath, root, onProgress);
      }

      final resolv = File('$root/etc/resolv.conf');
      await resolv.parent.create(recursive: true);
      await resolv.writeAsString('nameserver 1.1.1.1\nnameserver 8.8.8.8\n');

      await _silent(() => File(gzPath).delete());
      await _silent(() => File(tarPath).delete());
      if (!await _rootfsHealthy(root)) {
        throw StateError('Rootfs extraction failed verification');
      }
      await prefs.setBool('rootfs_downloading', false);
      await markAlpineInstalled();
    } catch (e) {
      await cleanupPartial();
      rethrow;
    }
  }

  // ── Terminal sessions ──────────────────────────────────────────────

  static Future<TerminalSession> create({
    required String id,
    int cols = 80,
    int rows = 24,
  }) async {
    final session = TerminalSession._(id, cols, rows);
    try {
      if (_isDesktop) {
        await session._openDesktop();
      } else {
        await session._open();
      }
    } catch (e) {
      await session.kill();
      // На Android 8/10 AXS часто падает. Пробуем нативный системный shell.
      if (!_isDesktop) {
        try {
          final fallback = TerminalSession._('${id}_fallback', cols, rows);
          await fallback._openUnsandboxed();
          fallback._output.add('[warning] engine failed: $e\n');
          fallback._output.add('[warning] using limited Android shell fallback.\n');
          return fallback;
        } catch (_) {}
      }
      rethrow;
    }
    return session;
  }

  static Future<TerminalSession> createUnsandboxed({required String id}) async {
    final session = TerminalSession._(id, 80, 24);
    try {
      await session._openUnsandboxed();
    } catch (_) {
      await session.kill();
      rethrow;
    }
    return session;
  }

  /// Write data to a terminal session by ID (used by plugins).
  static Future<void> write({required String id, required String data}) async {
    final s = _sockets[id];
    if (s == null) return;
    s.write(data);
  }

  /// Kill a terminal session by ID (used by plugins).
  static Future<void> kill({required String id}) async {
    final s = _sockets.remove(id);
    if (s != null) await s.close();
  }

  // ── Helpers ────────────────────────────────────────────────────────

  static Future<void> _silent(Future<Object?> Function() block) async {
    try {
      await block();
    } catch (_) {}
  }

  static String _alpineArch() {
    final abi = _abi();
    switch (abi) {
      case 'arm64-v8a':
        return 'aarch64';
      case 'armeabi-v7a':
        return 'armv7';
      case 'x86_64':
        return 'x86_64';
      case 'x86':
        return 'x86';
      default:
        return 'aarch64';
    }
  }

  static String _abi() {
    if (_isDesktop) {
      // На desktop Alpine не нужен, но функция вызывается только при
      // установке rootfs — на desktop installAlpine возвращает раньше.
      return 'x86_64';
    }
    final v = Platform.operatingSystemVersion.toLowerCase();
    if (v.contains('aarch64') || v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armv7') || v.contains('armeabi')) return 'armeabi-v7a';
    if (v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
    if (v.contains('i686') || v.contains('x86')) return 'x86';
    return 'arm64-v8a';
  }
}

/// Унифицированная обёртка над Android-WebSocket и desktop-процессом.
abstract class _BackendSession {
  Stream<String> get output;
  bool get isOpen;
  void write(String data);
  Future<void> close();
}

class _WebSocketBackend implements _BackendSession {
  final WebSocket ws;
  final _ctrl = StreamController<String>.broadcast();
  _WebSocketBackend(this.ws) {
    ws.listen(
      (data) {
        // PTY шлёт бинарные кадры; текстовые тоже принимаем.
        if (data is String) {
          _ctrl.add(data);
        } else if (data is List<int>) {
          _ctrl.add(utf8.decode(data, allowMalformed: true));
        }
      },
      onError: (e) => _ctrl.add('\n[stream error] $e\n'),
      onDone: () {
        if (!_ctrl.isClosed) _ctrl.add('\n[session ended]\n');
      },
    );
  }

  @override
  Stream<String> get output => _ctrl.stream;

  @override
  bool get isOpen => ws.readyState == WebSocket.open;

  @override
  void write(String data) {
    if (isOpen) ws.add(data);
  }

  @override
  Future<void> close() async {
    await ws.close();
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

class _DesktopBackend implements _BackendSession {
  final Process process;
  final _ctrl = StreamController<String>.broadcast();
  _DesktopBackend(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .listen((chunk) => _ctrl.add(chunk), onError: (e) {});
    process.stderr
        .transform(utf8.decoder)
        .listen((chunk) => _ctrl.add(chunk), onError: (e) {});
    process.exitCode.then((code) {
      if (!_ctrl.isClosed) {
        _ctrl.add('\n[process exited with code $code]\n');
      }
    });
  }

  @override
  Stream<String> get output => _ctrl.stream;

  @override
  bool get isOpen => true;

  @override
  void write(String data) {
    try {
      process.stdin.add(utf8.encode(data));
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      process.stdin.close();
    } catch (_) {}
    try {
      process.kill();
    } catch (_) {}
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

class TerminalSession {
  final String id;
  int cols;
  int rows;
  String? _pid; // pid PTY-сессии на стороне сервера
  StreamSubscription? _sub;
  final _output = StreamController<String>.broadcast();

  TerminalSession._(this.id, this.cols, this.rows);

  Stream<String> get output => _output.stream;

  Future<void> _open() async {
    _output.add('[terminal] starting engine…\n');
    await TerminalBridge._ensureAxs();
    final port = TerminalBridge._axsPort!;
    _output.add('[terminal] engine ready on port $port\n');
    _pid = await TerminalBridge._createAxsSession(port, cols, rows);
    _output.add('[terminal] session pid $_pid, attaching…\n');
    final ws = await _connectWs(port, _pid!);
    final backend = _WebSocketBackend(ws);
    TerminalBridge._sockets[id] = backend;
    _sub = backend.output.listen((chunk) => _output.add(chunk));
  }

  /// Запуск нативного системного shell как дочернего процесса.
  /// Используется на desktop-платформах (Linux/macOS/Windows) — никакого
  /// AXS и proot не нужно, всё работает нативно.
  Future<void> _openDesktop() async {
    final shell = _detectShell();
    final home = _homeDir();
    final process = await Process.start(
      shell.executable,
      shell.args,
      workingDirectory: home,
      environment: {
        'HOME': home,
        'TERM': 'xterm-256color',
        'PS1': r'\u@\h:\w\$ ',
        'PATH': Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin',
        'COLORTERM': 'truecolor',
      },
    );
    final backend = _DesktopBackend(process);
    TerminalBridge._sockets[id] = backend;
    _sub = backend.output.listen((chunk) => _output.add(chunk));

    _output.add(
        '[terminal] ${shell.label} launched (pid=${process.pid})\n');
  }

  Future<void> _openUnsandboxed() async {
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      await _openDesktop();
      return;
    }
    _sub = TerminalBridge._events
        .receiveBroadcastStream({'id': id})
        .listen(
          (event) {
            if (event is String) _output.add(event);
          },
          onError: (e) => _output.add('\n[stream error] $e\n'),
          onDone: () {
            if (!_output.isClosed) _output.add('\n[session ended]\n');
          },
        );

    final result = await TerminalBridge._method
        .invokeMethod<String>('createUnsandboxed', {'id': id});
    if (result != null && result != 'ok' && !result.startsWith('[terminal]')) {
      _output.add(result);
    }
  }

  Future<WebSocket> _connectWs(int port, String pid) async {
    const maxAttempts = 5;
    Exception? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await WebSocket.connect(
          'ws://127.0.0.1:$port/terminals/$pid',
        ).timeout(const Duration(seconds: 5));
      } on Exception catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    throw lastError ?? Exception('WebSocket connection failed');
  }

  Future<void> write(String data) async {
    await TerminalBridge.write(id: id, data: data);
  }

  Future<void> writeLine(String line) => write('$line\n');

  Future<void> resize(int c, int r) async {
    cols = c;
    rows = r;
    if (kIsWeb) return;
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      // ANSI resize не реализован в обёртке — обновляем только поля.
      return;
    }
    await TerminalBridge._ensureAxs();
    final port = TerminalBridge._axsPort;
    if (port == null || _pid == null) return;
    try {
      await http
          .post(
            Uri.parse('http://127.0.0.1:$port/terminals/$_pid/resize'),
            body: jsonEncode({'cols': c.toString(), 'rows': r.toString()}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> kill() async {
    runCatching(() => _sub?.cancel());
    _sub = null;
    // Завершаем PTY-сессию на стороне сервера.
    if (!kIsWeb &&
        (Platform.isAndroid)) {
      final port = TerminalBridge._axsPort;
      if (port != null && _pid != null) {
        try {
          await http
              .post(Uri.parse(
                  'http://127.0.0.1:$port/terminals/$_pid/terminate'))
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
    await TerminalBridge.kill(id: id);
    if (!_output.isClosed) await _output.close();
  }

  static _ShellSpec _detectShell() {
    final env = Platform.environment;
    final shellPath = env['SHELL'];
    if (shellPath != null && shellPath.isNotEmpty) {
      return _ShellSpec(shellPath, const [], _labelFromPath(shellPath));
    }
    if (Platform.isWindows) {
      // PowerShell или cmd.
      return _ShellSpec('cmd.exe', const ['/Q', '/K'], 'cmd.exe');
    }
    return _ShellSpec('/bin/sh', const ['-i'], '/bin/sh');
  }

  static String _labelFromPath(String p) {
    final base = p.split('/').last;
    return base.isEmpty ? p : base;
  }

  static String _homeDir() {
    try {
      final h = Platform.environment['HOME'];
      if (h != null && h.isNotEmpty) return h;
    } catch (_) {}
    return Directory.current.path;
  }
}

class _ShellSpec {
  final String executable;
  final List<String> args;
  final String label;
  const _ShellSpec(this.executable, this.args, this.label);
}

T? runCatching<T>(T Function() block) {
  try {
    return block();
  } catch (_) {
    return null;
  }
}
