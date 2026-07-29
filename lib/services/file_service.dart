import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SearchResult {
  final String path;
  final String fileName;
  final int line;
  final String match;
  SearchResult({required this.path, required this.fileName, required this.line, required this.match});
}

class SearchQuery {
  final String text;
  final bool caseSensitive;
  SearchQuery({required this.text, this.caseSensitive = false});
}

class FileNode {
  final String name;
  final String path;
  final bool isDir;
  List<FileNode> children;
  bool expanded;

  FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.children = const [],
    this.expanded = false,
  });
}

/// File-system entry points for XunCode.
///
/// Layout (Android 11+, no extra permissions):
///   privateRoot  = /storage/emulated/0/Android/data/com.xunkal1.xuncode/files
///                    ├── plugins/    cache/    rootfs/    proot/
///                    ├── prefs/      database/ logs/      tmp/
///   sharedRoot   = /storage/emulated/0/Shared/XunCode
///                    ├── Projects/   Downloads/  Backups/  Exports/  Languages/
///
/// Both paths are resolved on first call and cached for the lifetime of the
/// process. Call [FileService.ensureLayout] once at startup to make sure all
/// subfolders exist; subsequent reads are then synchronous through the
/// cached String-typed getters.
class FileService {
  static const _channel = MethodChannel('com.xunkal1.xuncode/storage');

  static String? _privateRoot;
  static String? _sharedRoot;
  static Completer<void>? _layoutReady;

  /// Idempotent: bootstraps both roots and the subfolder skeleton. Safe to
  /// call multiple times — the native side mkdirs are no-ops when paths exist.
  static Future<void> ensureLayout() async {
    if (_layoutReady != null) return _layoutReady!.future;
    final c = Completer<void>();
    _layoutReady = c;
    try {
      _privateRoot = await _channel.invokeMethod<String>('appDataDir');
      _sharedRoot = await _channel.invokeMethod<String>('sharedDir');
      await _channel.invokeMethod('ensureLayout');
    } catch (_) {
      // MethodChannel may not be wired in tests / desktop. Fall back to
      // path_provider so the rest of the app keeps working.
      final docs = await getApplicationDocumentsDirectory();
      _privateRoot = docs.path;
      _sharedRoot = '${docs.path}/Shared/XunCode';
      for (final sub in const [
        'plugins', 'cache', 'rootfs', 'proot', 'prefs', 'database', 'logs', 'tmp',
      ]) {
        await Directory('$_privateRoot/$sub').create(recursive: true);
      }
      for (final sub in const ['Projects', 'Downloads', 'Backups', 'Exports', 'Languages']) {
        try {
          await Directory('$_sharedRoot/$sub').create(recursive: true);
        } catch (_) {}
      }
    }
    c.complete();
  }

  /// Returns true on devices that don't need the permission (pre-Android 11)
  /// or after the user grants `MANAGE_EXTERNAL_STORAGE`. When false, the
  /// shared root falls back to the app-private external dir.
  static Future<bool> hasAllFilesAccess() async {
    try {
      return (await _channel.invokeMethod<bool>('hasAllFilesAccess')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android system page where the user can grant All Files Access.
  /// No-op on platforms / devices that don't support it.
  static Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  /// True when the resolved [sharedRoot] is the public Shared/XunCode path
  /// (visible in the user's file manager) vs the app-external fallback.
  static bool get sharedIsPublic =>
      (_sharedRoot ?? '').contains('/storage/emulated/0/Shared/XunCode');

  static String get sharedRoot {
    final r = _sharedRoot;
    if (r == null) throw StateError('FileService.ensureLayout() not called');
    return r;
  }

  static String get privateRoot {
    final r = _privateRoot;
    if (r == null) throw StateError('FileService.ensureLayout() not called');
    return r;
  }

  // Private (Android/data/.../files) subfolders — survive only until uninstall.
  static String get pluginsDir => '$privateRoot/plugins';
  static String get cacheDir   => '$privateRoot/cache';
  static String get rootfsDir  => '$privateRoot/rootfs';
  static String get prootDir   => '$privateRoot/proot';
  static String get prefsDir   => '$privateRoot/prefs';
  static String get dbDir      => '$privateRoot/database';
  static String get logsDir    => '$privateRoot/logs';
  static String get tmpDir     => '$privateRoot/tmp';
  static String get languagesInstallDir => '$privateRoot/languages';

  // Shared (visible to user, NOT removed on uninstall) subfolders.
  static String get projectsDir  => '$sharedRoot/Projects';
  static String get downloadsDir => '$sharedRoot/Downloads';
  static String get backupsDir   => '$sharedRoot/Backups';
  static String get exportsDir   => '$sharedRoot/Exports';
  static String get languagesDir => '$sharedRoot/Languages';

  /// Convenience: the user-facing projects folder as a Directory.
  static Future<Directory> projectsDirectory() async {
    await ensureLayout();
    final d = Directory(projectsDir);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ── Project ops (operate on sharedRoot/Projects by default) ───────────────

  static Future<String?> createProject(String name) async {
    await ensureLayout();
    final dir = Directory('$projectsDir/$name');
    if (await dir.exists()) return null;
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String?> createFile(String folderPath, String name) async {
    final file = File('$folderPath/$name');
    if (await file.exists()) return null;
    await file.create(recursive: true);
    return file.path;
  }

  static Future<Map<String, String>?> readFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return {'path': path, 'name': path.split('/').last, 'content': content};
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>?> importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.path == null) return null;
    final content = await File(file.path!).readAsString();
    return {'path': file.path!, 'name': file.name, 'content': content};
  }

  static Future<String?> importFolder() async {
    return FilePicker.platform.getDirectoryPath();
  }

  static Future<void> saveFile(String path, String content) async {
    await File(path).writeAsString(content);
  }

  static Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteFolder(String path) async {
    final d = Directory(path);
    if (await d.exists()) await d.delete(recursive: true);
  }

  static Future<void> renameNode(String oldPath, String newName) async {
    final parent = File(oldPath).parent.path;
    final newPath = '$parent/$newName';
    final type = await FileSystemEntity.type(oldPath);
    if (type == FileSystemEntityType.file) {
      await File(oldPath).rename(newPath);
    } else {
      await Directory(oldPath).rename(newPath);
    }
  }

  /// Async tree builder. Walks `dirPath` without blocking the UI thread on
  /// `listSync`/`statSync` for every file. Use [buildTreeSync] only if you
  /// need the result inside another sync call.
  static Future<List<FileNode>> buildTree(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    try {
      final entries = await dir.list(followLinks: false).toList();
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.split('/').last.compareTo(b.path.split('/').last);
      });
      final out = <FileNode>[];
      for (final e in entries) {
        final name = e.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          out.add(FileNode(
            name: name, path: e.path, isDir: true,
            children: await buildTree(e.path),
          ));
        } else {
          out.add(FileNode(name: name, path: e.path, isDir: false));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static List<FileNode> buildTreeSync(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    try {
      final entries = dir.listSync()
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.split('/').last.compareTo(b.path.split('/').last);
        });
      return entries.map((e) {
        final name = e.path.split('/').last;
        if (name.startsWith('.')) return null;
        if (e is Directory) {
          return FileNode(name: name, path: e.path, isDir: true, children: buildTreeSync(e.path));
        }
        return FileNode(name: name, path: e.path, isDir: false);
      }).whereType<FileNode>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SearchResult>> searchWorkspace(String root, String query,
      {bool caseSensitive = false}) async {
    final results = <SearchResult>[];
    if (query.trim().isEmpty) return results;
    final needle = caseSensitive ? query : query.toLowerCase();

    Future<void> walk(Directory dir) async {
      final children = dir.listSync();
      for (final entity in children) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          await walk(entity);
          continue;
        }
        try {
          final text = await File(entity.path).readAsString();
          final lines = const LineSplitter().convert(text);
          for (var i = 0; i < lines.length; i++) {
            final lineText = lines[i];
            final hay = caseSensitive ? lineText : lineText.toLowerCase();
            if (hay.contains(needle)) {
              results.add(SearchResult(
                path: entity.path,
                fileName: name,
                line: i + 1,
                match: lineText.trim(),
              ));
            }
          }
        } catch (_) {}
      }
    }

    final dir = Directory(root);
    if (await dir.exists()) {
      await walk(dir);
    }
    return results;
  }
}
