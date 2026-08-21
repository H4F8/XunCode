import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();
  // singleton factory removed - use SettingsService.instance

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  ThemeMode get themeMode {
    final v = _prefs.getString('theme') ?? 'dark';
    return v == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  double get fontSize => _prefs.getDouble('fontSize') ?? 14.0;
  String get fontFamily => _prefs.getString('fontFamily') ?? 'JetBrains Mono';
  int get tabSize => _prefs.getInt('tabSize') ?? 2;
  bool get wordWrap => _prefs.getBool('wordWrap') ?? true;
  String get autoSave => _prefs.getString('autoSave') ?? 'off';
  bool get torEnabled => _prefs.getBool('torEnabled') ?? false;
  bool get developerMode => _prefs.getBool('developerMode') ?? false;
  String get language => _prefs.getString('language') ?? 'system';

  bool get completionEnabled => _prefs.getBool('completion.enabled') ?? true;
  int get completionDelayMs => _prefs.getInt('completion.delayMs') ?? 150;
  int get completionMaxItems => _prefs.getInt('completion.maxItems') ?? 50;

  // Маркеры одноразовых bootstrap-операций. Хранятся под нейтральными
  // ключами, чтобы при следующем апгрейде можно было поднять версию и
  // переинициализировать без миграции.
  String? get bundleVersion => _prefs.getString('lang.bundleVersion');
  Future<void> setBundleVersion(String v) => _prefs.setString('lang.bundleVersion', v);

  bool get alpineInstalled => _prefs.getBool('alpine.installed') ?? false;
  Future<void> setAlpineInstalled(bool v) => _prefs.setBool('alpine.installed', v);

  /// Красный огонёк мягкого обновления. Гасится просмотром диалога
  /// или обновлением, зажигается при появлении нового релиза.
  bool get hasUpdate => _prefs.getBool('update.has_update') ?? false;
  Future<void> setHasUpdate(bool v) => _prefs.setBool('update.has_update', v);

  Future<void> set<T>(String key, T value) async {
    if (value is String) await _prefs.setString(key, value);
    else if (value is bool) await _prefs.setBool(key, value);
    else if (value is int) await _prefs.setInt(key, value);
    else if (value is double) await _prefs.setDouble(key, value);
  }
}
