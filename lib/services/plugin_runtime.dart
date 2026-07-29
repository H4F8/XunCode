import 'dart:async';

import '../models/plugin.dart';
import 'editor_bridge.dart';
import 'plugin_sandbox.dart';
import 'plugin_service.dart';

class PluginRuntime {
  PluginRuntime._();
  static final PluginRuntime instance = PluginRuntime._();

  final Map<String, PluginSandbox> _active = {};
  EditorBridge? _editor;
  void Function(String message, {bool isError})? _uiNotifier;
  Future<void> Function(String path)? _openFile;
  Future<String?> Function(String? title, String? placeholder, String? value)? _showInputBox;
  Future<String?> Function(List<String> items, String? title)? _showQuickPick;

  void attachEditor(EditorBridge bridge) {
    _editor = bridge;
  }

  void attachUi(void Function(String message, {bool isError}) notifier) {
    _uiNotifier = notifier;
  }

  void attachOpenFile(Future<void> Function(String path) openFile) {
    _openFile = openFile;
  }

  void attachInputBox(Future<String?> Function(String? title, String? placeholder, String? value) fn) {
    _showInputBox = fn;
  }

  void attachQuickPick(Future<String?> Function(List<String> items, String? title) fn) {
    _showQuickPick = fn;
  }

  void detachUi() {
    _editor = null;
    _uiNotifier = null;
    _openFile = null;
    _showInputBox = null;
    _showQuickPick = null;
  }

  Future<String?> Function(String? title, String? placeholder, String? value)? get inputBox => _showInputBox;
  Future<String?> Function(List<String> items, String? title)? get quickPick => _showQuickPick;

  Future<void> activateInstalled() async {
    final list = await PluginService.listInstalled();
    for (final p in list) {
      unawaited(activate(p));
    }
  }

  Future<void> activate(InstalledPlugin p) async {
    if (_editor == null) return;
    if (_active.containsKey(p.id)) return;
    final sandbox = PluginSandbox(
      plugin: p,
      editor: _editor!,
      onUiMessage: (msg, {bool isError = false}) {
        _uiNotifier?.call(msg, isError: isError);
      },
      onOpenFile: _openFile,
      onShowInputBox: _showInputBox,
      onShowQuickPick: _showQuickPick,
    );
    try {
      await sandbox.load();
      _active[p.id] = sandbox;
    } catch (e) {
      _uiNotifier?.call('Plugin "${p.name}" failed to load: $e', isError: true);
      await sandbox.dispose();
    }
  }

  bool isActive(String id) => _active.containsKey(id);

  Set<String> get activeIds => Set.unmodifiable(_active.keys);

  Future<void> reloadAll() async {
    await deactivateAll();
    await activateInstalled();
  }

  Future<void> deactivate(String id) async {
    final s = _active.remove(id);
    if (s != null) await s.dispose();
  }

  Future<void> deactivateAll() async {
    for (final s in _active.values.toList()) {
      await s.dispose();
    }
    _active.clear();
  }

  Future<void> fireSave(String path) async {
    for (final s in _active.values) {
      await s.fireHook('onSave', path);
    }
  }

  Future<void> fireFileOpen(String path) async {
    for (final s in _active.values) {
      await s.fireHook('onFileOpen', path);
    }
  }

  Future<void> fireEditorChange(String content) async {
    for (final s in _active.values) {
      await s.fireHook('onEditorChange', content);
    }
  }

  Future<void> fireCursorMove(int line, int column) async {
    for (final s in _active.values) {
      await s.fireHook('onCursorMove', {'line': line, 'column': column});
    }
  }

  Future<void> fireSettingsChange(Map<String, dynamic> settings) async {
    for (final s in _active.values) {
      await s.fireHook('onSettingsChange', settings);
    }
  }

  /// Map of pluginId → command IDs registered by that plugin.
  Map<String, Set<String>> commandsByPlugin() {
    final out = <String, Set<String>>{};
    _active.forEach((id, sandbox) {
      out[id] = sandbox.commands;
    });
    return out;
  }

  /// Flat list of "<pluginId>:<commandId>" entries for a quick-pick.
  List<String> allCommandIds() {
    final out = <String>[];
    _active.forEach((id, sandbox) {
      for (final c in sandbox.commands) {
        out.add('$id:$c');
      }
    });
    return out;
  }

  /// Executes a command; accepts both "pluginId:commandId" and bare commandId
  /// (in which case the first matching plugin wins).
  Future<bool> executeCommand(String entry) async {
    String? pluginId;
    String commandId = entry;
    final colon = entry.indexOf(':');
    if (colon > 0) {
      pluginId = entry.substring(0, colon);
      commandId = entry.substring(colon + 1);
    }
    if (pluginId != null) {
      final sandbox = _active[pluginId];
      if (sandbox == null) return false;
      if (!sandbox.commands.contains(commandId)) return false;
      await sandbox.executeCommand(commandId);
      return true;
    }
    for (final s in _active.values) {
      if (s.commands.contains(commandId)) {
        await s.executeCommand(commandId);
        return true;
      }
    }
    return false;
  }
}
