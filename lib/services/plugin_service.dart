import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin.dart';
import 'file_service.dart';
import 'review_service.dart';

class PluginService {
  static const _apiBase = 'https://xuncode-market.vercel.app';
  static const _installedKey = 'installed_plugins_v2';
  static const _permsKey = 'plugin_permissions';

  /// Returns the set of permissions the user has granted for a plugin.
  static Future<Set<String>> getGrantedPermissions(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_permsKey:$pluginId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.map((e) => e.toString()).toSet();
    } catch (_) {}
    return {};
  }

  /// Grant a permission to a plugin (user-approved).
  static Future<void> grantPermission(String pluginId, String permission) async {
    final granted = await getGrantedPermissions(pluginId);
    granted.add(permission);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_permsKey:$pluginId', jsonEncode(granted.toList()));
  }

  /// Revoke a permission.
  static Future<void> revokePermission(String pluginId, String permission) async {
    final granted = await getGrantedPermissions(pluginId);
    granted.remove(permission);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_permsKey:$pluginId', jsonEncode(granted.toList()));
  }

  /// Check if a plugin has a specific permission granted.
  static Future<bool> hasPermission(String pluginId, String permission) async {
    final granted = await getGrantedPermissions(pluginId);
    return granted.contains(permission);
  }

  /// Returns permissions declared in plugin.json that haven't been granted yet.
  static Future<List<String>> getPendingPermissions(InstalledPlugin plugin) async {
    final granted = await getGrantedPermissions(plugin.id);
    return plugin.permissions.where((p) => !granted.contains(p)).toList();
  }

  // In-memory marketplace cache. The list endpoint is small and rarely changes,
  // so we hold the result for a short window so navigating in/out of the
  // marketplace screen doesn't refetch on every entry.
  static const _marketTtl = Duration(minutes: 2);
  static List<Plugin>? _marketCache;
  static DateTime? _marketCacheAt;

  static Future<Directory> _pluginsDir() async {
    await FileService.ensureLayout();
    final dir = Directory(FileService.pluginsDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _tmpDir() async {
    await FileService.ensureLayout();
    final dir = Directory(FileService.tmpDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<Plugin>> fetchMarketplace({String? query, bool forceRefresh = false}) async {
    final cached = _marketCache;
    final cachedAt = _marketCacheAt;
    if (!forceRefresh && cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _marketTtl) {
      return _filterPlugins(cached, query);
    }
    try {
      final uri = Uri.parse('$_apiBase/api/plugins/list');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return cached != null ? _filterPlugins(cached, query) : [];
      final body = jsonDecode(res.body);
      if (body is! List) return [];
      final list = body
          .whereType<Map>()
          .map((e) => Plugin.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _marketCache = list;
      _marketCacheAt = DateTime.now();
      return _filterPlugins(list, query);
    } catch (_) {
      return cached != null ? _filterPlugins(cached, query) : [];
    }
  }

  static List<Plugin> _filterPlugins(List<Plugin> source, String? query) {
    if (query == null || query.trim().isEmpty) return source;
    final q = query.toLowerCase().trim();
    return source.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        p.tags.any((t) => t.toLowerCase().contains(q))).toList();
  }

  static void invalidateMarketplaceCache() {
    _marketCache = null;
    _marketCacheAt = null;
  }

  static Future<Plugin?> fetchInfo(String id) async {
    try {
      final uri = Uri.parse('$_apiBase/api/plugins/info?id=$id');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      return Plugin.fromJson(Map<String, dynamic>.from(body));
    } catch (_) {
      return null;
    }
  }

  static Future<InstalledPlugin> installFromLocalFolder(String folderPath) async {
    final src = Directory(folderPath);
    if (!await src.exists()) {
      throw Exception('folder does not exist');
    }
    final manifestFile = File('${src.path}/plugin.json');
    if (!await manifestFile.exists()) {
      throw Exception('plugin.json not found in selected folder');
    }
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map) {
      throw Exception('plugin.json must be an object');
    }
    final id = manifest['id']?.toString();
    final version = manifest['version']?.toString() ?? '1.0.0';
    final mainName = manifest['main']?.toString() ?? 'main.js';
    if (id == null || id.isEmpty) {
      throw Exception('plugin.json missing required "id"');
    }
    final mainFile = File('${src.path}/$mainName');
    if (!await mainFile.exists()) {
      throw Exception('main file "$mainName" not found');
    }

    final pluginsBase = await _pluginsDir();
    final dest = Directory('${pluginsBase.path}/$id');
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.create(recursive: true);

    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = entity.path.substring(src.path.length);
      if (rel.isEmpty) continue;
      final outPath = '${dest.path}$rel';
      if (entity is File) {
        final f = File(outPath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(await entity.readAsBytes());
      } else if (entity is Directory) {
        await Directory(outPath).create(recursive: true);
      }
    }

    final installed = InstalledPlugin(
      id: id,
      version: version,
      localPath: dest.path,
      githubUrl: 'local://${src.path}',
      manifest: Map<String, dynamic>.from(manifest),
    );
    await _saveInstalled(installed);
    invalidateMarketplaceCache();
    return installed;
  }

  static Future<InstalledPlugin> installFromGithub(String githubUrl) async {    final cleaned = _cleanGithubUrl(githubUrl);
    final tmpDir = await _tmpDir();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final zipFile = File('${tmpDir.path}/plugin-$stamp.zip');

    Uint8List? bytes;
    Object? lastError;
    for (final branch in const ['main', 'master']) {
      final url = '$cleaned/archive/refs/heads/$branch.zip';
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          bytes = res.bodyBytes;
          break;
        }
        lastError = 'HTTP ${res.statusCode} on $branch branch';
      } catch (e) {
        lastError = e;
      }
    }
    if (bytes == null) {
      throw Exception('Failed to download plugin: $lastError');
    }

    await zipFile.writeAsBytes(bytes, flush: true);
    final extractDir = Directory('${tmpDir.path}/plugin-extract-$stamp');
    if (await extractDir.exists()) await extractDir.delete(recursive: true);
    await extractDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = '${extractDir.path}/${entry.name}';
      if (entry.isFile) {
        final f = File(outPath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(entry.content as List<int>, flush: false);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    final inner = await _findPluginRoot(extractDir);
    if (inner == null) {
      await zipFile.delete().catchError((_) => zipFile);
      await extractDir.delete(recursive: true).catchError((_) => extractDir);
      throw Exception('plugin.json not found in repository');
    }

    final manifestFile = File('${inner.path}/plugin.json');
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map) {
      throw Exception('plugin.json must be an object');
    }
    final id = manifest['id']?.toString();
    final version = manifest['version']?.toString() ?? '1.0.0';
    final mainName = manifest['main']?.toString() ?? 'main.js';
    if (id == null || id.isEmpty) {
      throw Exception('plugin.json missing required "id"');
    }
    final mainFile = File('${inner.path}/$mainName');
    if (!await mainFile.exists()) {
      throw Exception('main file "$mainName" not found');
    }

    final pluginsBase = await _pluginsDir();
    final dest = Directory('${pluginsBase.path}/$id');
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.create(recursive: true);

    await for (final entity in inner.list(recursive: true, followLinks: false)) {
      final rel = entity.path.substring(inner.path.length);
      if (rel.isEmpty) continue;
      final outPath = '${dest.path}$rel';
      if (entity is File) {
        final f = File(outPath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(await entity.readAsBytes());
      } else if (entity is Directory) {
        await Directory(outPath).create(recursive: true);
      }
    }

    await zipFile.delete().catchError((_) => zipFile);
    await extractDir.delete(recursive: true).catchError((_) => extractDir);

    final installed = InstalledPlugin(
      id: id,
      version: version,
      localPath: dest.path,
      githubUrl: cleaned,
      manifest: Map<String, dynamic>.from(manifest),
    );

    await _saveInstalled(installed);
    invalidateMarketplaceCache();
    unawaited(_reportDownload(id));
    return installed;
  }

  static Future<void> _reportDownload(String pluginId) async {
    try {
      final token = await ReviewService.getUserToken();
      await http
          .post(
            Uri.parse('$_apiBase/api/plugins/download'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'pluginId': pluginId, 'userToken': token}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort: a missed counter increment is not worth surfacing.
    }
  }

  static Future<void> uninstall(String id) async {
    final list = await listInstalled();
    final filtered = list.where((p) => p.id != id).toList();
    await _writeAll(filtered);
    final pluginsBase = await _pluginsDir();
    final dir = Directory('${pluginsBase.path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
    invalidateMarketplaceCache();
  }

  static Future<List<InstalledPlugin>> listInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_installedKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return [];
      return parsed
          .whereType<Map>()
          .map((e) => InstalledPlugin.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isInstalled(String id) async {
    final list = await listInstalled();
    return list.any((p) => p.id == id);
  }

  static Future<String> readPluginCode(InstalledPlugin p) async {
    final f = File('${p.localPath}/${p.mainFile}');
    return f.readAsString();
  }

  static Future<void> _saveInstalled(InstalledPlugin p) async {
    final list = await listInstalled();
    list.removeWhere((e) => e.id == p.id);
    list.add(p);
    await _writeAll(list);
  }

  static Future<void> _writeAll(List<InstalledPlugin> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _installedKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static String _cleanGithubUrl(String url) {
    var u = url.trim();
    if (u.endsWith('.git')) u = u.substring(0, u.length - 4);
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  static Future<Directory?> _findPluginRoot(Directory extractDir) async {
    final direct = File('${extractDir.path}/plugin.json');
    if (await direct.exists()) return extractDir;
    await for (final entity in extractDir.list()) {
      if (entity is Directory) {
        final f = File('${entity.path}/plugin.json');
        if (await f.exists()) return entity;
      }
    }
    return null;
  }
}
