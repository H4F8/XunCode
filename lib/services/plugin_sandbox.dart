import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin.dart';
import '../services/file_service.dart';
import '../services/settings_service.dart';
import 'editor_bridge.dart';
import 'plugin_service.dart';
import 'terminal_service.dart';

typedef UiCallback = void Function(String message, {bool isError});
typedef OpenFileCallback = Future<void> Function(String path);
typedef InputBoxCallback = Future<String?> Function(String? title, String? placeholder, String? value);
typedef QuickPickCallback = Future<String?> Function(List<String> items, String? title);

class PluginSandbox {
  final InstalledPlugin plugin;
  final EditorBridge editor;
  final UiCallback onUiMessage;
  final OpenFileCallback? onOpenFile;
  final InputBoxCallback? onShowInputBox;
  final QuickPickCallback? onShowQuickPick;

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _ctrl;
  final _registeredCommands = <String>{};
  final _ready = Completer<void>();

  PluginSandbox({
    required this.plugin,
    required this.editor,
    required this.onUiMessage,
    this.onOpenFile,
    this.onShowInputBox,
    this.onShowQuickPick,
  });

  Future<void> load() async {
    final code = await PluginService.readPluginCode(plugin);
    final html = _bootstrapHtml(plugin.id, code);
    _headless = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
      ),
      onWebViewCreated: (c) {
        _ctrl = c;
        _registerHostHandlers(c);
      },
      onLoadStop: (_, __) {
        if (!_ready.isCompleted) _ready.complete();
      },
    );
    await _headless!.run();
    return _ready.future;
  }

  Future<void> dispose() async {
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _ctrl = null;
  }

  Future<void> executeCommand(String id) async {
    if (!_registeredCommands.contains(id)) return;
    await _ctrl?.evaluateJavascript(
      source: 'window.__plugin_run_command && window.__plugin_run_command(${jsonEncode(id)})',
    );
  }

  Set<String> get commands => Set.unmodifiable(_registeredCommands);

  void _registerHostHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'host.invoke',
      callback: (args) async {
        if (args.isEmpty) return {'ok': false, 'error': 'no args'};
        final method = args[0]?.toString() ?? '';
        final params = args.length > 1 && args[1] is Map
            ? Map<String, dynamic>.from(args[1] as Map)
            : <String, dynamic>{};
        try {
          final result = await _dispatch(method, params);
          return {'ok': true, 'value': result};
        } catch (e) {
          return {'ok': false, 'error': e.toString()};
        }
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'host.registerCommand',
      callback: (args) {
        if (args.isEmpty) return null;
        final id = args[0]?.toString() ?? '';
        if (id.isNotEmpty) _registeredCommands.add(id);
        return null;
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permission map: which methods require which permission
  // ─────────────────────────────────────────────────────────────────────────
  static const _permMap = <String, String>{
    // fs write
    'fs.writeFile': 'fs.write', 'fs.appendFile': 'fs.write',
    'fs.deleteFile': 'fs.write', 'fs.deleteDir': 'fs.write',
    'fs.createDir': 'fs.write', 'fs.copy': 'fs.write',
    'fs.move': 'fs.write', 'fs.delete': 'fs.write',
    // terminal
    'terminal.run': 'terminal', 'terminal.create': 'terminal',
    'terminal.send': 'terminal', 'terminal.kill': 'terminal',
    // process
    'process.spawn': 'process', 'process.exec': 'process',
    // settings write
    'settings.set': 'settings.write',
    // storage write
    'storage.set': 'storage.write', 'storage.delete': 'storage.write',
    'storage.clear': 'storage.write', 'storage.setBinary': 'storage.write',
  };

  Future<void> _checkPermission(String method) async {
    final required = _permMap[method];
    if (required == null) return; // no permission needed
    final granted = await PluginService.getGrantedPermissions(plugin.id);
    if (!granted.contains(required)) {
      // Auto-grant for plugins that declare it in plugin.json
      if (plugin.permissions.contains(required)) {
        await PluginService.grantPermission(plugin.id, required);
        return;
      }
      throw Exception('Permission denied: $required (request it in plugin.json permissions[])');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dispatch — маршрутизация вызовов JS → Dart
  // ─────────────────────────────────────────────────────────────────────────
  Future<dynamic> _dispatch(String method, Map<String, dynamic> p) async {
    await _checkPermission(method);
    switch (method) {
      // ── editor ──────────────────────────────────────────────────────
      case 'editor.getText':
        return editor.getText();
      case 'editor.setText':
        await editor.setText(p['text']?.toString() ?? '');
        return null;
      case 'editor.getSelection':
        return editor.getSelection();
      case 'editor.setSelection':
        await editor.setSelection(
          (p['startLine'] as num?)?.toInt() ?? 1,
          (p['startColumn'] as num?)?.toInt() ?? 1,
          (p['endLine'] as num?)?.toInt() ?? 1,
          (p['endColumn'] as num?)?.toInt() ?? 1,
        );
        return null;
      case 'editor.insertText':
        await editor.insertText(p['text']?.toString() ?? '');
        return null;
      case 'editor.replaceRange':
        await editor.replaceRange(
          (p['startLine'] as num?)?.toInt() ?? 1,
          (p['startColumn'] as num?)?.toInt() ?? 1,
          (p['endLine'] as num?)?.toInt() ?? 1,
          (p['endColumn'] as num?)?.toInt() ?? 1,
          p['text']?.toString() ?? '',
        );
        return null;
      case 'editor.getLine':
        return editor.getLine((p['line'] as num?)?.toInt() ?? 1);
      case 'editor.getLines':
        return editor.getLines();
      case 'editor.getLanguage':
        return editor.getLanguage();
      case 'editor.setLanguage':
        await editor.setLanguage(p['language']?.toString() ?? 'plaintext');
        return null;
      case 'editor.formatDocument':
        await editor.formatDocument();
        return null;
      case 'editor.getCursorPosition':
        return editor.getCursorPosition();
      case 'editor.setCursorPosition':
        await editor.setCursorPosition(
          (p['line'] as num?)?.toInt() ?? 1,
          (p['column'] as num?)?.toInt() ?? 1,
        );
        return null;
      case 'editor.executeCommand':
        await editor.executeCommand(p['command']?.toString() ?? '');
        return null;
      case 'editor.openFile':
        if (onOpenFile != null) await onOpenFile!(p['path']?.toString() ?? '');
        return null;
      case 'editor.getOpenFiles':
        return <String>[]; // TODO: track open files
      case 'editor.closeFile':
        return null; // TODO

      // ── ui ──────────────────────────────────────────────────────────
      case 'ui.showMessage':
        onUiMessage(p['text']?.toString() ?? '');
        return null;
      case 'ui.showError':
        onUiMessage(p['text']?.toString() ?? '', isError: true);
        return null;
      case 'ui.showWarning':
        onUiMessage('⚠ ${p['text']?.toString() ?? ''}');
        return null;
      case 'ui.showInputBox':
        return onShowInputBox?.call(
          p['title']?.toString(),
          p['placeholder']?.toString(),
          p['value']?.toString(),
        );
      case 'ui.showQuickPick':
        final items = (p['items'] is List)
            ? (p['items'] as List).map((e) => e.toString()).toList()
            : <String>[];
        return onShowQuickPick?.call(items, p['title']?.toString());
      case 'ui.showProgress':
        // fire-and-forget: plugin manages its own progress UI via messages
        return null;
      case 'ui.createStatusBarItem':
        return {'setText': () {}, 'dispose': () {}};
      case 'ui.createWebViewPanel':
        return {'postMessage': () {}, 'dispose': () {}};
      case 'ui.showDiff':
        return {'accepted': false}; // plugin shows diff via its own UI
      case 'ui.withProgress':
        await (p['task'] as Future?)?.catchError((_) {});
        return null;

      // ── storage ─────────────────────────────────────────────────────
      case 'storage.get':
        return _storageGet(p['key']?.toString() ?? '');
      case 'storage.set':
        await _storageSet(p['key']?.toString() ?? '', p['value']?.toString() ?? '');
        return null;
      case 'storage.delete':
        await _storageDelete(p['key']?.toString() ?? '');
        return null;
      case 'storage.clear':
        await _storageClear();
        return null;
      case 'storage.getBinary':
        return _storageGetBinary(p['key']?.toString() ?? '');
      case 'storage.setBinary':
        await _storageSetBinary(
          p['key']?.toString() ?? '',
          p['data'] is List<int> ? p['data'] as List<int> : [],
        );
        return null;

      // ── http ────────────────────────────────────────────────────────
      case 'http.get':
        return _httpGet(p);
      case 'http.post':
        return _httpPost(p);
      case 'http.put':
        return _httpPut(p);
      case 'http.patch':
        return _httpPatch(p);
      case 'http.delete':
        return _httpDelete(p);
      case 'http.stream':
        return _httpStream(p);
      case 'http.webSocket':
        return {'id': ''}; // WS handled differently, placeholder

      // ── fs ──────────────────────────────────────────────────────────
      case 'fs.readFile':
        return _fsReadFile(p['path']?.toString() ?? '');
      case 'fs.writeFile':
        return _fsWriteFile(p['path']?.toString() ?? '', p['data']?.toString() ?? '');
      case 'fs.deleteFile':
        return _fsDeleteFile(p['path']?.toString() ?? '');
      case 'fs.delete':
        return _fsDelete(p['path']?.toString() ?? '');
      case 'fs.createDir':
        return _fsCreateDir(p['path']?.toString() ?? '');
      case 'fs.deleteDir':
        return _fsDeleteDir(p['path']?.toString() ?? '');
      case 'fs.exists':
        return _fsExists(p['path']?.toString() ?? '');
      case 'fs.listDir':
        return _fsListDir(p['path']?.toString() ?? '');
      case 'fs.copy':
        return _fsCopy(p['from']?.toString() ?? '', p['to']?.toString() ?? '');
      case 'fs.move':
        return _fsMove(p['from']?.toString() ?? '', p['to']?.toString() ?? '');
      case 'fs.watch':
        return {'dispose': () {}};
      case 'fs.getRoot':
        await FileService.ensureLayout();
        return FileService.projectsDir;
      case 'fs.getCurrent':
        return FileService.projectsDir;
      case 'fs.stat':
        return _fsStat(p['path']?.toString() ?? '');
      case 'fs.appendFile':
        return _fsAppendFile(p['path']?.toString() ?? '', p['data']?.toString() ?? '');
      case 'fs.readDir':
        return _fsListDir(p['path']?.toString() ?? '');

      // ── workspace ───────────────────────────────────────────────────
      case 'workspace.getRoot':
        await FileService.ensureLayout();
        return FileService.projectsDir;
      case 'workspace.findFiles':
        return _workspaceFindFiles(p['pattern']?.toString() ?? '');
      case 'workspace.openFile':
        if (onOpenFile != null) await onOpenFile!(p['path']?.toString() ?? '');
        return null;
      case 'workspace.getOpenFiles':
        return <String>[];

      // ── terminal ────────────────────────────────────────────────────
      case 'terminal.run':
        return _terminalRun(p['cmd']?.toString() ?? '', p['cwd']?.toString());
      case 'terminal.create':
        return TerminalBridge.create(id: 'plugin-${plugin.id}', cols: 80, rows: 24)
            .then((_) => 'plugin-${plugin.id}');
      case 'terminal.send':
        TerminalBridge.write(id: 'plugin-${plugin.id}', data: p['input']?.toString() ?? '');
        return null;
      case 'terminal.kill':
        await TerminalBridge.kill(id: 'plugin-${plugin.id}');
        return null;
      case 'terminal.onOutput':
        // Plugin subscribes via hook, returns dispose fn
        return {'dispose': () {}};

      // ── process ─────────────────────────────────────────────────────
      case 'process.spawn':
        return _processSpawn(p['cmd']?.toString() ?? '', p['args'], p['cwd']?.toString(), p['env']);
      case 'process.exec':
        return _processExec(p['cmd']?.toString() ?? '', p['cwd']?.toString());

      // ── settings ────────────────────────────────────────────────────
      case 'settings.get':
        return _settingsGet(p['key']?.toString() ?? '');
      case 'settings.set':
        await _settingsSet(p['key']?.toString() ?? '', p['value']);
        return null;
      case 'settings.getAll':
        return _settingsGetAll();
      case 'settings.onDidChange':
        return {'dispose': () {}};

      default:
        throw Exception('Unknown method: $method');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FS helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> _fsReadFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<void> _fsWriteFile(String path, String data) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(data);
  }

  Future<void> _fsAppendFile(String path, String data) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(data, mode: FileMode.append);
  }

  Future<bool> _fsDelete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) return false;
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
    return true;
  }

  Future<bool> _fsDeleteFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  Future<void> _fsCreateDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  Future<bool> _fsDeleteDir(String path) async {
    final d = Directory(path);
    if (!await d.exists()) return false;
    await d.delete(recursive: true);
    return true;
  }

  Future<bool> _fsExists(String path) async {
    if (await File(path).exists()) return true;
    if (await Directory(path).exists()) return true;
    return false;
  }

  Future<List<Map<String, Object>>> _fsListDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final out = <Map<String, Object>>[];
    await for (final entity in dir.list(followLinks: false)) {
      out.add({
        'name': entity.path.split('/').last,
        'path': entity.path,
        'isDir': entity is Directory,
      });
    }
    return out;
  }

  Future<void> _fsCopy(String from, String to) async {
    final src = File(from);
    if (await src.exists()) {
      await Directory(to).parent.create(recursive: true);
      await src.copy(to);
    } else {
      // Copy directory recursively
      final srcDir = Directory(from);
      if (!await srcDir.exists()) return;
      await for (final entity in srcDir.list(recursive: true)) {
        final rel = entity.path.substring(srcDir.path.length + 1);
        final dstPath = '$to/$rel';
        if (entity is Directory) {
          await Directory(dstPath).create(recursive: true);
        } else if (entity is File) {
          await Directory(dstPath).parent.create(recursive: true);
          await File(entity.path).copy(dstPath);
        }
      }
    }
  }

  Future<void> _fsMove(String from, String to) async {
    final type = await FileSystemEntity.type(from);
    if (type == FileSystemEntityType.file) {
      await File(from).rename(to);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    }
  }

  Future<Map<String, Object>?> _fsStat(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    final stat = await f.stat();
    return {
      'size': stat.size,
      'modified': stat.modified.toIso8601String(),
      'created': stat.changed.toIso8601String(),
      'isFile': stat.type == FileSystemEntityType.file,
      'isDir': stat.type == FileSystemEntityType.directory,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Workspace helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<String>> _workspaceFindFiles(String pattern) async {
    await FileService.ensureLayout();
    final root = Directory(FileService.projectsDir);
    final results = <String>[];
    final regex = _globToRegExp(pattern);
    if (!await root.exists()) return results;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(root.path.length + 1);
      if (regex.hasMatch(rel)) results.add(entity.path);
      if (results.length >= 1000) break;
    }
    return results;
  }

  static RegExp _globToRegExp(String pattern) {
    if (pattern.isEmpty) return RegExp(r'.*');
    final sb = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          sb.write('.*');
          i += 2;
          continue;
        }
        sb.write('[^/]*');
      } else if (c == '?') {
        sb.write('[^/]');
      } else if ('.+()[]{}^\$\\|'.contains(c)) {
        sb.write('\\$c');
      } else {
        sb.write(c);
      }
      i++;
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Storage helpers (namespaced)
  // ─────────────────────────────────────────────────────────────────────────
  String get _prefix => 'plugin:${plugin.id}:';

  Future<String?> _storageGet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  Future<void> _storageSet(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  Future<void> _storageDelete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  Future<void> _storageClear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(k);
    }
  }

  Future<Uint8List?> _storageGetBinary(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('$_prefix$key');
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  Future<void> _storageSetBinary(String key, List<int> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', base64Encode(data));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP helpers
  // ─────────────────────────────────────────────────────────────────────────
  Map<String, String> _parseHeaders(dynamic headers) {
    if (headers is! Map) return <String, String>{};
    return headers.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<Map<String, dynamic>> _httpGet(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final res = await http.get(Uri.parse(url), headers: _parseHeaders(p['headers']))
        .timeout(Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 30));
    return {'status': res.statusCode, 'body': res.body, 'headers': res.headers};
  }

  Future<Map<String, dynamic>> _httpPost(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final body = p['body'];
    final encoded = body is String ? body : jsonEncode(body);
    final res = await http.post(Uri.parse(url), headers: _parseHeaders(p['headers']), body: encoded)
        .timeout(Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 30));
    return {'status': res.statusCode, 'body': res.body, 'headers': res.headers};
  }

  Future<Map<String, dynamic>> _httpPut(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final body = p['body'];
    final encoded = body is String ? body : jsonEncode(body);
    final res = await http.put(Uri.parse(url), headers: _parseHeaders(p['headers']), body: encoded)
        .timeout(Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 30));
    return {'status': res.statusCode, 'body': res.body, 'headers': res.headers};
  }

  Future<Map<String, dynamic>> _httpPatch(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final body = p['body'];
    final encoded = body is String ? body : jsonEncode(body);
    final res = await http.patch(Uri.parse(url), headers: _parseHeaders(p['headers']), body: encoded)
        .timeout(Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 30));
    return {'status': res.statusCode, 'body': res.body, 'headers': res.headers};
  }

  Future<Map<String, dynamic>> _httpDelete(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final res = await http.delete(Uri.parse(url), headers: _parseHeaders(p['headers']))
        .timeout(Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 30));
    return {'status': res.statusCode, 'body': res.body, 'headers': res.headers};
  }

  Future<Map<String, dynamic>> _httpStream(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final headers = _parseHeaders(p['headers']);
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(headers);
    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(
        Duration(seconds: (p['timeout'] as num?)?.toInt() ?? 60),
      );
      final chunks = <int>[];
      await for (final chunk in streamed.stream) {
        chunks.addAll(chunk);
        // onChunk callback could be invoked here if we had a mechanism
      }
      final body = utf8.decode(chunks);
      return {'status': streamed.statusCode, 'body': body};
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Terminal / Process helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _terminalRun(String cmd, String? cwd) async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', cmd],
        workingDirectory: cwd,
        runInShell: false,
      ).timeout(const Duration(minutes: 5));
      return {
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
        'exitCode': result.exitCode,
      };
    } catch (e) {
      return {'stdout': '', 'stderr': e.toString(), 'exitCode': -1};
    }
  }

  Future<Map<String, dynamic>> _processSpawn(String cmd, dynamic args, String? cwd, dynamic env) async {
    final argList = (args is List) ? args.map((e) => e.toString()).toList() : <String>[];
    try {
      final result = await Process.run(
        cmd,
        argList,
        workingDirectory: cwd,
        environment: env is Map ? env.map((k, v) => MapEntry(k.toString(), v.toString())) : null,
        runInShell: true,
      ).timeout(const Duration(minutes: 10));
      return {
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
        'exitCode': result.exitCode,
      };
    } catch (e) {
      return {'stdout': '', 'stderr': e.toString(), 'exitCode': -1};
    }
  }

  Future<Map<String, dynamic>> _processExec(String cmd, String? cwd) async {
    return _terminalRun(cmd, cwd);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings helpers
  // ─────────────────────────────────────────────────────────────────────────
  dynamic _settingsGet(String key) {
    final s = SettingsService.instance;
    switch (key) {
      case 'theme': return s.themeMode == ThemeMode.light ? 'light' : 'dark';
      case 'fontSize': return s.fontSize;
      case 'fontFamily': return s.fontFamily;
      case 'tabSize': return s.tabSize;
      case 'wordWrap': return s.wordWrap;
      case 'autoSave': return s.autoSave;
      case 'developerMode': return s.developerMode;
      case 'language': return s.language;
      case 'completionEnabled': return s.completionEnabled;
      case 'completionDelayMs': return s.completionDelayMs;
      case 'completionMaxItems': return s.completionMaxItems;
      default: return null;
    }
  }

  Future<void> _settingsSet(String key, dynamic value) async {
    // Currently settings changes are best-effort; full persistence requires
    // wiring each key to SharedPreferences. For now we silently accept.
  }

  Map<String, dynamic> _settingsGetAll() {
    return {
      'theme': SettingsService.instance.themeMode == ThemeMode.light ? 'light' : 'dark',
      'fontSize': SettingsService.instance.fontSize,
      'fontFamily': SettingsService.instance.fontFamily,
      'tabSize': SettingsService.instance.tabSize,
      'wordWrap': SettingsService.instance.wordWrap,
      'autoSave': SettingsService.instance.autoSave,
      'developerMode': SettingsService.instance.developerMode,
      'language': SettingsService.instance.language,
      'completionEnabled': SettingsService.instance.completionEnabled,
      'completionDelayMs': SettingsService.instance.completionDelayMs,
      'completionMaxItems': SettingsService.instance.completionMaxItems,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JS bootstrap, hook firing, public helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> fireHook(String name, [Object? data]) async {
    await _ctrl?.evaluateJavascript(
      source:
          'window.__plugin_fire_hook && window.__plugin_fire_hook(${jsonEncode(name)}, ${jsonEncode(data)})',
    );
  }

  String _bootstrapHtml(String pluginId, String code) {
    const runtime = r'''
      (function () {
        const pending = new Map();
        let nextId = 1;

        function invoke(method, params) {
          return window.flutter_inappwebview.callHandler('host.invoke', method, params || {})
            .then(r => {
              if (!r) return null;
              if (r.ok === false) throw new Error(r.error || 'invoke failed');
              return r.value;
            });
        }

        const commands = new Map();
        const hooks = {};

        function on(name, cb) {
          (hooks[name] = hooks[name] || []).push(cb);
        }

        window.__plugin_fire_hook = function (name, data) {
          (hooks[name] || []).forEach(cb => { try { cb(data); } catch (e) { console.error(e); } });
        };

        window.__plugin_run_command = function (id) {
          const cb = commands.get(id);
          if (cb) { try { cb(); } catch (e) { console.error(e); } }
        };

        // ── editor ──────────────────────────────────────────────────────
        const editor = {
          getText: () => invoke('editor.getText'),
          setText: (t) => invoke('editor.setText', { text: String(t) }),
          getSelection: () => invoke('editor.getSelection'),
          setSelection: (sl, sc, el, ec) => invoke('editor.setSelection',
            { startLine: sl, startColumn: sc, endLine: el, endColumn: ec }),
          insertText: (t) => invoke('editor.insertText', { text: String(t) }),
          replaceRange: (sl, sc, el, ec, t) => invoke('editor.replaceRange',
            { startLine: sl, startColumn: sc, endLine: el, endColumn: ec, text: String(t) }),
          getLine: (l) => invoke('editor.getLine', { line: l }),
          getLines: () => invoke('editor.getLines'),
          getLanguage: () => invoke('editor.getLanguage'),
          setLanguage: (id) => invoke('editor.setLanguage', { language: String(id) }),
          formatDocument: () => invoke('editor.formatDocument'),
          getCursorPosition: () => invoke('editor.getCursorPosition'),
          setCursorPosition: (l, c) => invoke('editor.setCursorPosition', { line: l, column: c }),
          executeCommand: (cmd) => invoke('editor.executeCommand', { command: String(cmd) }),
          openFile: (path) => invoke('editor.openFile', { path: String(path) }),
          getOpenFiles: () => invoke('editor.getOpenFiles'),
          closeFile: (path) => invoke('editor.closeFile', { path: String(path) }),
          getValue: () => invoke('editor.getText'),
          setValue: (v) => invoke('editor.setText', { text: String(v) }),
          getCursor: () => invoke('editor.getCursorPosition'),
          setCursor: (line, col) => invoke('editor.setCursorPosition', { line: line, column: col }),
        };

        // ── ui ──────────────────────────────────────────────────────────
        const ui = {
          showMessage: (text) => invoke('ui.showMessage', { text: String(text) }),
          showError: (text) => invoke('ui.showError', { text: String(text) }),
          showWarning: (text) => invoke('ui.showWarning', { text: String(text) }),
          showInputBox: (opts) => invoke('ui.showInputBox', {
            title: opts && opts.title ? String(opts.title) : null,
            placeholder: opts && opts.placeholder ? String(opts.placeholder) : null,
            value: opts && opts.value ? String(opts.value) : null,
          }),
          showQuickPick: (items, opts) => invoke('ui.showQuickPick', {
            items: Array.isArray(items) ? items.map(String) : [],
            title: opts && opts.title ? String(opts.title) : null,
          }),
          showProgress: (title) => invoke('ui.showProgress', { title: String(title) }),
          showDiff: (opts) => invoke('ui.showDiff', {
            original: opts && opts.original ? String(opts.original) : '',
            modified: opts && opts.modified ? String(opts.modified) : '',
          }),
          withProgress: (opts, task) => invoke('ui.withProgress', {
            title: opts && opts.title ? String(opts.title) : '',
          }),
          createStatusBarItem: () => ({ setText: () => {}, dispose: () => {} }),
          createWebViewPanel: (opts) => ({
            html: opts && opts.html ? String(opts.html) : '',
            setTitle: () => {},
            postMessage: () => {},
            onMessage: (cb) => ({ dispose: () => {} }),
            update: (h) => {},
            close: () => {},
            dispose: () => {},
          }),
          createPanel: (opts) => ({
            html: opts && opts.html ? String(opts.html) : '',
            setTitle: (t) => {},
            postMessage: (m) => {},
            onMessage: (cb) => ({ dispose: () => {} }),
            update: (h) => {},
            close: () => {},
            dispose: () => {},
          }),
        };

        // ── storage ─────────────────────────────────────────────────────
        const storage = {
          get: (k) => invoke('storage.get', { key: String(k) }),
          set: (k, v) => invoke('storage.set', { key: String(k), value: String(v) }),
          delete: (k) => invoke('storage.delete', { key: String(k) }),
          clear: () => invoke('storage.clear'),
          getBinary: (k) => invoke('storage.getBinary', { key: String(k) }),
          setBinary: (k, data) => invoke('storage.setBinary', { key: String(k), data: data || [] }),
        };

        // ── http ────────────────────────────────────────────────────────
        const http = {
          get: (url, headers) => invoke('http.get', { url: String(url), headers: headers || {} }),
          post: (url, body, headers) => invoke('http.post',
            { url: String(url), body: body, headers: headers || {} }),
          put: (url, body, headers) => invoke('http.put',
            { url: String(url), body: body, headers: headers || {} }),
          patch: (url, body, headers) => invoke('http.patch',
            { url: String(url), body: body, headers: headers || {} }),
          delete: (url, headers) => invoke('http.delete',
            { url: String(url), headers: headers || {} }),
          stream: (url, opts) => invoke('http.stream',
            { url: String(url), headers: (opts && opts.headers) || {}, timeout: opts && opts.timeout || 60 }),
          webSocket: (url) => ({
            send: () => {},
            onMessage: (cb) => ({ dispose: () => {} }),
            onError: (cb) => ({ dispose: () => {} }),
            close: () => {},
          }),
        };

        // ── fs ──────────────────────────────────────────────────────────
        const fs = {
          readFile: (path) => invoke('fs.readFile', { path: String(path) }),
          writeFile: (path, data) => invoke('fs.writeFile', { path: String(path), data: String(data) }),
          appendFile: (path, data) => invoke('fs.appendFile', { path: String(path), data: String(data) }),
          deleteFile: (path) => invoke('fs.deleteFile', { path: String(path) }),
          deleteDir: (path) => invoke('fs.deleteDir', { path: String(path) }),
          delete: (path) => invoke('fs.delete', { path: String(path) }),
          createDir: (path) => invoke('fs.createDir', { path: String(path) }),
          exists: (path) => invoke('fs.exists', { path: String(path) }),
          listDir: (path) => invoke('fs.listDir', { path: String(path) }),
          readDir: (path) => invoke('fs.readDir', { path: String(path) }),
          copy: (from, to) => invoke('fs.copy', { from: String(from), to: String(to) }),
          move: (from, to) => invoke('fs.move', { from: String(from), to: String(to) }),
          stat: (path) => invoke('fs.stat', { path: String(path) }),
          watch: (path, cb) => ({ dispose: () => {} }),
          getRoot: () => invoke('fs.getRoot'),
          getCurrent: () => invoke('fs.getCurrent'),
        };

        // ── workspace ───────────────────────────────────────────────────
        const workspace = {
          getRoot: () => invoke('workspace.getRoot'),
          openFile: (path) => invoke('workspace.openFile', { path: String(path) }),
          findFiles: (pattern) => invoke('workspace.findFiles', { pattern: String(pattern || '**/*') }),
          onDidSaveFile: (cb) => on('onSave', cb),
          onDidOpenFile: (cb) => on('onFileOpen', cb),
        };

        // ── terminal ────────────────────────────────────────────────────
        const terminal = {
          run: (cmd, cwd) => invoke('terminal.run', { cmd: String(cmd), cwd: cwd || null }),
          create: (name) => invoke('terminal.create', { name: String(name) }),
          send: (input) => invoke('terminal.send', { input: String(input) }),
          kill: () => invoke('terminal.kill'),
          onOutput: (name, cb) => on('terminal.' + name, cb),
        };

        // ── process ─────────────────────────────────────────────────────
        const process = {
          spawn: (cmd, args, opts) => invoke('process.spawn', {
            cmd: String(cmd),
            args: Array.isArray(args) ? args : [],
            cwd: opts && opts.cwd ? String(opts.cwd) : null,
            env: opts && opts.env ? opts.env : null,
          }),
          exec: (cmd, opts) => invoke('process.exec', {
            cmd: String(cmd),
            cwd: opts && opts.cwd ? String(opts.cwd) : null,
          }),
        };

        // ── settings ────────────────────────────────────────────────────
        const settings = {
          get: (key) => invoke('settings.get', { key: String(key) }),
          set: (key, value) => invoke('settings.set', { key: String(key), value: value }),
          getAll: () => invoke('settings.getAll'),
          onDidChange: (cb) => {
            on('onSettingsChange', cb);
            return { dispose: () => {} };
          },
        };

        // ── commands & hooks ────────────────────────────────────────────
        const commandsApi = {
          registerCommand: (id, cb) => {
            commands.set(id, cb);
            window.flutter_inappwebview.callHandler('host.registerCommand', id);
          },
          executeCommand: (id) => {
            const cb = commands.get(id);
            return cb ? Promise.resolve(cb()) : Promise.resolve(null);
          },
        };

        // ── assemble ────────────────────────────────────────────────────
        window.xuncode = {
          editor, ui, storage, http, fs, workspace, terminal, process, settings,
          commands: commandsApi,
          hooks: {
            onSave: (cb) => on('onSave', cb),
            onFileOpen: (cb) => on('onFileOpen', cb),
            onEditorChange: (cb) => on('onEditorChange', cb),
            onCursorMove: (cb) => on('onCursorMove', cb),
            onSettingsChange: (cb) => on('onSettingsChange', cb),
          },
        };
        window.vscode = window.xuncode; // обратная совместимость старых плагинов

        const moduleObj = { exports: {} };
        window.module = moduleObj;
        window.exports = moduleObj.exports;

        window.__plugin_activate = function () {
          try {
            const ex = window.module.exports || window.exports || {};
            if (typeof ex.activate === 'function') {
              ex.activate(window.xuncode);
            }
          } catch (e) { console.error('plugin activate failed', e); }
        };
      })();
    ''';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"></head><body>
<script>$runtime</script>
<script>
try {
  $code
} catch (e) {
  console.error('plugin top-level error', e);
}
</script>
<script>window.__plugin_activate && window.__plugin_activate();</script>
</body></html>
''';
  }
}
