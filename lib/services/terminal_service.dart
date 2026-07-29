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

    final dir = await getApplicationSupportDirectory();
    final axsDir = Directory('${dir.path}/axs');
    final axsFile = File('${axsDir.path}/axs');
    if (await axsFile.exists()) return axsFile;

    await axsDir.create(recursive: true);
    final byteData = await rootBundle.load('assets/axs/axs');
    await axsFile.writeAsBytes(byteData.buffer.asUint8List());
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

  static Future<void> _ensureAxs() async {
    if (_axsProcess != null) return;
    if (_isDesktop) return; // no AXS on desktop
    final axs = await _axsBinary();
    final rootfs = await rootfsPath();
    final nativeDir =
        await _method.invokeMethod<String>('getNativeLibraryDir') ??
            '/data/app/com.xunkal1.xuncode/lib/arm64';
    final prootBin = '$nativeDir/libproot.so';

    // AXS не всегда стартует стабильно на Android 8/10/12: иногда бинарник
    // падает сразу, иногда не пишет порт. Если порт не получен — бросаем
    // ошибку, и вызывающий код должен упасть обратно на системный shell.
    _axsProcess = await Process.start(axs.path, [
      '-p', '0',
      '-c', '/bin/sh',
    ], environment: {
      'PROOT_PATH': prootBin,
      'ROOTFS': rootfs,
      'LD_LIBRARY_PATH': nativeDir,
    });

    final portFuture = _axsProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere(
          (line) => RegExp(r'started on .*:(\d+)').hasMatch(line),
          orElse: () => '',
        )
        .then((line) {
      final match = RegExp(r'started on .*:(\d+)').firstMatch(line);
      if (match != null) {
        _axsPort = int.parse(match.group(1)!);
      }
      return _axsPort;
    });

    final stderrFuture = _axsProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .then((line) => line)
        .catchError((_) => '');

    try {
      final result = await Future.any([
        Future.wait([portFuture, stderrFuture]),
        Future.delayed(
            _axsTimeout, () => throw TimeoutException('AXS start timeout')),
      ]);
      if (result is List) {
        final port = result[0] as int?;
        final err = result[1] as String?;
        if (port == null || port <= 0) {
          _axsProcess?.kill();
          _axsProcess = null;
          _axsPort = null;
          throw Exception('AXS did not report a port${err?.isNotEmpty == true ? ": $err" : ""}');
        }
      }
    } catch (_) {
      _axsProcess?.kill();
      _axsProcess = null;
      _axsPort = null;
      rethrow;
    }
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
        if (root.isNotEmpty) {
          final marker = File('$root/.installed');
          if (await marker.exists()) {
            // Проверим, что /bin/sh реально существует — иногда маркер есть,
            // а rootfs побит.
            final binSh = File('$root/bin/sh');
            if (await binSh.exists()) return true;
          }
          final dir = Directory(root);
          if (await dir.exists() && await _hasContent(dir)) {
            await marker.writeAsString('ok');
            return true;
          }
        }
      } catch (_) {}
      await prefs.setBool('alpine.installed', false);
    }
    final v = await _method.invokeMethod<bool>('isAlpineInstalled');
    final installed = v ?? false;
    if (installed) await prefs.setBool('alpine.installed', true);
    return installed;
  }

  static Future<bool> _hasContent(Directory dir) async {
    try {
      await for (final _ in dir.list(followLinks: false)) {
        return true;
      }
    } catch (_) {}
    return false;
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

  /// Скачивает Alpine minirootfs при первом запуске (Android only).
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

    final root = await rootfsPath();
    final rootDir = Directory(root);
    if (!await rootDir.exists()) await rootDir.create(recursive: true);

    final hasBin = await Directory('$root/bin').exists();
    final hasEtc = await Directory('$root/etc').exists();
    if (hasBin || hasEtc) {
      onProgress?.call(1.0, 'Found existing rootfs');
      await markAlpineInstalled();
      return;
    }

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

      onProgress?.call(0.0, 'Extracting');
      final tarStream = InputFileStream(tarPath);
      try {
        final archive = TarDecoder().decodeBuffer(tarStream);
        final total = archive.length;
        var done = 0;
        for (final entry in archive) {
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: url),
              reason: 'cancelled during extraction',
            );
          }
          final outPath = '$root/${entry.name}';
          if (entry.isFile) {
            final f = File(outPath);
            await f.parent.create(recursive: true);
            await f.writeAsBytes(entry.content as List<int>, flush: false);
          } else {
            await Directory(outPath).create(recursive: true);
          }
          done++;
          if (done % 200 == 0) {
            onProgress?.call(done / total, 'Extracting');
          }
        }
        onProgress?.call(1.0, 'Extracting');
      } finally {
        await tarStream.close();
      }

      final resolv = File('$root/etc/resolv.conf');
      await resolv.parent.create(recursive: true);
      await resolv.writeAsString('nameserver 1.1.1.1\nnameserver 8.8.8.8\n');

      await _silent(() => File(gzPath).delete());
      await _silent(() => File(tarPath).delete());
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
          fallback._output.add('[warning] proot/AXS failed: $e\n');
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
        if (data is String) _ctrl.add(data);
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
  StreamSubscription? _sub;
  final _output = StreamController<String>.broadcast();

  TerminalSession._(this.id, this.cols, this.rows);

  Stream<String> get output => _output.stream;

  Future<void> _open() async {
    await TerminalBridge._ensureAxs();
    final port = TerminalBridge._axsPort ?? 8767;
    final ws = await _connectWs(port);
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

  Future<WebSocket> _connectWs(int port) async {
    const maxAttempts = 5;
    Exception? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await WebSocket.connect(
          'ws://127.0.0.1:$port/terminals/new',
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
    final port = TerminalBridge._axsPort ?? 8767;
    await http.post(
      Uri.parse('http://127.0.0.1:$port/terminals/$id/resize'),
      body: jsonEncode({'cols': c, 'rows': r}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<void> kill() async {
    runCatching(() => _sub?.cancel());
    _sub = null;
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
