import 'package:flutter/material.dart';
import '../services/plugin_runtime.dart';
import '../services/settings_service.dart';

class SettingsModel extends ChangeNotifier {
  final SettingsService _svc;

  SettingsModel(this._svc);

  ThemeMode get themeMode => _svc.themeMode;
  double get fontSize => _svc.fontSize;
  String get fontFamily => _svc.fontFamily;
  String get editorTheme => _svc.editorTheme;
  int get tabSize => _svc.tabSize;
  bool get wordWrap => _svc.wordWrap;
  String get autoSave => _svc.autoSave;
  bool get developerMode => _svc.developerMode;
  String get language => _svc.language;

  bool get completionEnabled => _svc.completionEnabled;
  int get completionDelayMs => _svc.completionDelayMs;
  int get completionMaxItems => _svc.completionMaxItems;

  Future<void> set<T>(String key, T value) async {
    await _svc.set(key, value);
    notifyListeners();
    PluginRuntime.instance.fireSettingsChange({
      'key': key,
      'value': value,
    });
  }
}
