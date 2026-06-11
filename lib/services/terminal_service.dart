import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';

/// AXS (Acode eXecution Server) — обходит noexec на Android 13+ через memfd_create.
/// AXS запускается как отдельный процесс и выполняет команды внутри proot-песочницы.
///
/// Бинарник AXS лежит в assets/axs/axs, при первом запуске копируется в filesDir/axs/axs.
/// proot-библиотеки (libproot.so, libtalloc.so и др.) встроены в APK через jniLibs.
class TerminalBridge {
  static const _method = MethodChannel('com.xunkal1.xuncode/terminal');
  static const _events = EventChannel('com.xunkal1.xuncode/terminal/events');

  static int? _axsPort;
  static Process? _axsProcess;
  static final Map<String, WebSocket> _sockets = {};
  static const _axsTimeout = Duration(seconds: 10);

  // ── AXS binary management ──────────────────────────────────────────

  static Future<File> _axsBinary() async {
    // Сначала пробуем libaxs.so из nativeLibraryDir (обход noexec/W^X)
    final native = await _axsBinaryFromNativeLib();
    if (native != null) return native;

    // Fallback: копируем из assets
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
      final nativeDir = await _method.invokeMethod<String>('getNativeLibraryDir') ??
          '/data/app/com.xunkal1.xuncode/lib/arm64';
      final file = File('$nativeDir/libaxs.so');
      if (await file.exists() && await file.length() > 0) return file;
    } catch (_) {}
    return null;
  }

  static Future<void> _ensureAxs() async {
    if (_axsProcess != null) return;
    final axs = await _axsBinary();
    final rootfs = await rootfsPath();
    final nativeDir = await _method.invokeMethod<String>('getNativeLibraryDir') ??
        '/data/app/com.xunkal1.xuncode/lib/arm64';
    final prootBin = '$nativeDir/libproot.so';

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

    await Future.any([
      portFuture,
      Future.delayed(_axsTimeout, () => throw TimeoutException('AXS start timeout')),
    ]);
  }

  static Future<WebSocket> _connectWs(int port) async {
    return WebSocket.connect(
      'ws://127.0.0.1:$port/terminals/new',
    ).timeout(const Duration(seconds: 5));
  }

  /// Путь к rootfs Alpine
  static Future<String> rootfsPath() async {
    return await _method.invokeMethod<String>('rootfsPath') ?? '';
  }

  // ── Alpine rootfs ───────────────────────────────────────────────────

  static Future<bool> isAlpineInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('alpine.installed') == true) {
      try {
        final root = await rootfsPath();
        if (root.isNotEmpty) {
          final marker = File('$root/.installed');
          if (await marker.exists()) return true;
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
    await _method.invokeMethod('markAlpineInstalled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alpine.installed', true);
  }

  /// Скачивает Alpine minirootfs при первом запуске (с прогрессом и cancel)
  static Future<void> installAlpine({
    void Function(double progress, String stage)? onProgress,
    CancelToken? cancelToken,
  }) async {
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

  // ── Terminal sessions via AXS ──────────────────────────────────────

  static Future<TerminalSession> create({
    required String id,
    int cols = 80,
    int rows = 24,
  }) async {
    await _ensureAxs();
    final session = TerminalSession._(id, cols, rows);
    await session._open();
    return session;
  }

  static Future<TerminalSession> createUnsandboxed({required String id}) async {
    final session = TerminalSession._(id, 80, 24);
    await session._openUnsandboxed();
    return session;
  }

  /// Write data to a terminal session by ID (used by plugins).
  static Future<void> write({required String id, required String data}) async {
    final ws = _sockets[id];
    if (ws != null) {
      ws.add(data);
    }
  }

  /// Kill a terminal session by ID (used by plugins).
  static Future<void> kill({required String id}) async {
    final ws = _sockets.remove(id);
    if (ws != null) {
      await ws.close();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  static Future<void> _silent(Future<Object?> Function() block) async {
    try { await block(); } catch (_) {}
  }

  static String _alpineArch() {
    final abi = _abi();
    switch (abi) {
      case 'arm64-v8a': return 'aarch64';
      case 'armeabi-v7a': return 'armv7';
      case 'x86_64': return 'x86_64';
      case 'x86': return 'x86';
      default: return 'aarch64';
    }
  }

  static String _abi() {
    final v = Platform.operatingSystemVersion.toLowerCase();
    if (v.contains('aarch64') || v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armv7') || v.contains('armeabi')) return 'armeabi-v7a';
    if (v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
    if (v.contains('i686') || v.contains('x86')) return 'x86';
    return 'arm64-v8a';
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
    final ws = await TerminalBridge._connectWs(port);
    TerminalBridge._sockets[id] = ws;

    ws.listen(
      (data) {
        if (data is String) _output.add(data);
      },
      onError: (e) => _output.add('\n[stream error] $e\n'),
      onDone: () {
        if (!_output.isClosed) _output.add('\n[session ended]\n');
      },
    );
  }

  Future<void> _openUnsandboxed() async {
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

    final result = await TerminalBridge._method.invokeMethod<String>('createUnsandboxed', {
      'id': id,
    });
    if (result != null && result != 'ok' && !result.startsWith('[terminal]')) {
      _output.add(result);
    }
  }

  Future<void> write(String data) async {
    await TerminalBridge.write(id: id, data: data);
  }

  Future<void> writeLine(String line) => write('$line\n');

  Future<void> resize(int c, int r) async {
    cols = c;
    rows = r;
    final port = TerminalBridge._axsPort ?? 8767;
    await http.post(
      Uri.parse('http://127.0.0.1:$port/terminals/$id/resize'),
      body: jsonEncode({'cols': c, 'rows': r}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<void> kill() async {
    runCatching(() => _sub?.cancel());
    await TerminalBridge.kill(id: id);
    if (!_output.isClosed) await _output.close();
  }
}

T? runCatching<T>(T Function() block) {
  try {
    return block();
  } catch (_) {
    return null;
  }
}
