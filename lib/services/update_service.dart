import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'platform_info.dart';

/// Источник установки приложения.
///
/// Определяется на Android через PackageManager: `ru.vk.store` означает
/// RuStore, всё остальное (null, браузер, проводник) — GitHub. На desktop
/// платформа всегда [InstallPlatform.pc].
enum InstallPlatform { github, rustore, pc }

extension InstallPlatformX on InstallPlatform {
  /// Тег платформы, как он пишется в маркере `[HARD UPDATE: ...]`.
  String get tag {
    switch (this) {
      case InstallPlatform.github:
        return 'GITHUB';
      case InstallPlatform.rustore:
        return 'RUSTORE';
      case InstallPlatform.pc:
        return 'PC';
    }
  }
}

/// Ассет (файл) релиза на GitHub.
class ReleaseAsset {
  final String name;
  final String downloadUrl;

  const ReleaseAsset({required this.name, required this.downloadUrl});

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: json['name'] as String? ?? '',
        downloadUrl: json['browser_download_url'] as String? ?? '',
      );
}

/// Релиз из GitHub API.
class GithubRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool prerelease;
  final List<ReleaseAsset> assets;
  final List<int> versionParts;

  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    required this.assets,
    required this.versionParts,
  });

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .toList();
    return GithubRelease(
      tagName: tag,
      name: json['name'] as String? ?? tag,
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      prerelease: json['prerelease'] as bool? ?? false,
      assets: assets,
      versionParts: UpdateService.parseVersion(tag),
    );
  }

  /// Есть ли в описании маркер критического обновления.
  bool get isHardUpdate =>
      hardUpdatePlatforms(body).isNotEmpty;

  /// Список платформ из маркера `[HARD UPDATE: GITHUB, RUSTORE]`.
  /// Пустой список — маркера нет.
  ///
  /// Скобки опциональны: принимается и «голый» вариант на отдельной
  /// строке — `HARD UPDATE: GITHUB`, как его часто пишут вручную при
  /// редактировании релиза на GitHub.
  static List<String> hardUpdatePlatforms(String body) {
    final m = RegExp(
      r'\[\s*HARD\s+UPDATE\s*:\s*([A-Za-z_,\s]+?)\s*\]|^\s*HARD\s+UPDATE\s*:\s*([A-Za-z_,\s]+?)\s*$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(body);
    if (m == null) return const [];
    return (m.group(1) ?? m.group(2) ?? '')
        .split(',')
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Прямая ссылка на скачивание для платформы пользователя.
  ///
  /// Android: предпочитаем nonroot-APK, затем любой APK.
  /// Desktop: AppImage, затем deb/rpm/tar.gz, иначе страница релиза.
  String downloadUrlFor(InstallPlatform platform) {
    if (platform == InstallPlatform.rustore) return htmlUrl;
    if (platform == InstallPlatform.github) {
      for (final pattern in ['nonroot', '.apk']) {
        for (final a in assets) {
          if (a.name.toLowerCase().contains(pattern)) return a.downloadUrl;
        }
      }
      return htmlUrl;
    }
    for (final ext in ['.appimage', '.deb', '.rpm', '.tar.gz']) {
      for (final a in assets) {
        if (a.name.toLowerCase().endsWith(ext)) return a.downloadUrl;
      }
    }
    return htmlUrl;
  }
}

/// Результат фоновой проверки обновлений.
class UpdateCheckResult {
  final InstallPlatform platform;
  final String currentVersion;

  /// Все релизы строго новее установленной версии.
  final List<GithubRelease> newReleases;

  /// Критические релизы, блокирующие платформу пользователя.
  final List<GithubRelease> hardReleases;

  const UpdateCheckResult({
    required this.platform,
    required this.currentVersion,
    required this.newReleases,
    required this.hardReleases,
  });

  bool get hasUpdate => newReleases.isNotEmpty;
  bool get hasHardUpdate => hardReleases.isNotEmpty;

  /// Самый свежий релиз (первый в списке от GitHub API).
  GithubRelease? get latest => newReleases.isEmpty ? null : newReleases.first;

  /// Склеенный Markdown всех критических релизов.
  String get hardMarkdown =>
      hardReleases.map((r) => r.body.trim()).join('\n\n---\n\n');
}

/// Автономный движок умных обновлений XunCode через GitHub API.
///
/// Управление полностью из Markdown-описаний релизов организации H4F8:
/// обычный текст — мягкое обновление, маркер `[HARD UPDATE: GITHUB, RUSTORE]`
/// в первой строке — тотальная блокировка для перечисленных платформ.
class UpdateService {
  UpdateService._();

  static const _channel = MethodChannel('com.xunkal1.xuncode/update');
  static const _releasesUrl =
      'https://api.github.com/repos/H4F8/XunCode/releases?per_page=100';

  /// Версия по умолчанию для desktop-сборок; на Android берётся из
  /// PackageManager, поэтому здесь она только запасная.
  static const _fallbackVersion = '1.1.8';

  /// Определить источник установки (Шаг 3.1 ТЗ).
  static Future<InstallPlatform> detectPlatform() async {
    if (!PlatformInfo.isAndroid) return InstallPlatform.pc;
    try {
      final src = await _channel.invokeMethod<String>('getInstallSource');
      if (src != null && src.trim() == 'ru.vk.store') {
        return InstallPlatform.rustore;
      }
      return InstallPlatform.github;
    } catch (_) {
      // Нет канала (например, тесты) — считаем сборку с GitHub.
      return InstallPlatform.github;
    }
  }

  /// Текущая версия приложения.
  static Future<String> appVersion() async {
    if (PlatformInfo.isAndroid) {
      try {
        final v = await _channel.invokeMethod<String>('getAppVersion');
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
    }
    return const String.fromEnvironment(
      'XUNCODE_VERSION',
      defaultValue: _fallbackVersion,
    );
  }

  /// Разбор версии вида `v2.2.1` / `2.2` в список чисел.
  static List<int> parseVersion(String raw) {
    final m =
        RegExp(r'^v?(\d+(?:\.\d+)*)', caseSensitive: false).firstMatch(raw.trim());
    if (m == null) return const [];
    return m.group(1)!.split('.').map(int.parse).toList();
  }

  /// Сравнение версий: > 0 если [a] новее [b], < 0 если старше, 0 при равенстве.
  static int compareVersions(List<int> a, List<int> b) {
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Полная проверка обновлений (Шаги 3.2–3.3 ТЗ).
  ///
  /// При любой сетевой ошибке возвращает null: приложение обязано молча
  /// работать офлайн, никакие экраны блокировки не показываются.
  static Future<UpdateCheckResult?> check({
    String? currentVersion,
    InstallPlatform? platform,
    http.Client? client,
  }) async {
    final http.Client httpClient = client ?? http.Client();
    try {
      platform ??= await detectPlatform();
      currentVersion ??= await appVersion();
      final current = parseVersion(currentVersion);
      if (current.isEmpty) return null;

      final releases = await _fetchReleases(httpClient);

      // Только релизы строго новее текущей версии юзера.
      final newReleases = releases
          .where((r) =>
              r.versionParts.isNotEmpty &&
              compareVersions(r.versionParts, current) > 0)
          .toList(growable: false);

      // Перебираем ВСЕ пропущенные релизы без break: если критических
      // несколько, их тексты склеиваются в один Markdown.
      final hard = <GithubRelease>[];
      for (final r in newReleases) {
        final platforms = GithubRelease.hardUpdatePlatforms(r.body);
        if (platforms.contains(platform.tag)) hard.add(r);
      }

      return UpdateCheckResult(
        platform: platform,
        currentVersion: currentVersion,
        newReleases: newReleases,
        hardReleases: hard,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<List<GithubRelease>> _fetchReleases(http.Client client) async {
    final resp = await client.get(
      Uri.parse(_releasesUrl),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'XunCode-Updater',
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('GitHub API ${resp.statusCode}');
    }
    final list = jsonDecodeList(resp.body);
    return list.map(GithubRelease.fromJson).toList();
  }
}

List<Map<String, dynamic>> jsonDecodeList(String body) {
  final decoded = const JsonDecoder().convert(body);
  if (decoded is! List) throw const FormatException('expected JSON array');
  return decoded.whereType<Map<String, dynamic>>().toList();
}
