import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/settings_model.dart';
import '../services/platform_info.dart';

/// Desktop menu bar for Linux, macOS and Windows.
///
/// Provides File / Edit / View / Terminal / Plugins / Tools / Help menus wired
/// up to the editor through global callbacks. Activated with `Alt+F` (File)
/// by default and also drawn as a top bar.
class DesktopMenuBar extends StatelessWidget {
  final VoidCallback onNewProject;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onSave;
  final VoidCallback onSaveAll;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleTerminal;
  final VoidCallback onCommandPalette;
  final VoidCallback onSettings;
  final VoidCallback onMarketplace;
  final VoidCallback onAbout;
  final VoidCallback onReloadPlugins;

  const DesktopMenuBar({
    super.key,
    required this.onNewProject,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onSave,
    required this.onSaveAll,
    required this.onToggleSidebar,
    required this.onToggleTerminal,
    required this.onCommandPalette,
    required this.onSettings,
    required this.onMarketplace,
    required this.onAbout,
    required this.onReloadPlugins,
  });

  final bool _isMacOS = PlatformInfo.isMacOS;
  String get _shortcutMeta => _isMacOS ? 'Cmd' : 'Ctrl';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(bottom: BorderSide(color: Color(0xFF252526))),
      ),
      child: Row(
        children: [
          _menuButton(context, 'File', [
            _mi('New Project', Icons.folder_outlined, onNewProject,
                '$_shortcutMeta+Shift+N'),
            _mi('Open File…', Icons.note_add_outlined, onOpenFile,
                '$_shortcutMeta+O'),
            _mi('Open Folder…', Icons.folder_open, onOpenFolder,
                '$_shortcutMeta+K $_shortcutMeta+O'),
            const PopupMenuDivider(),
            _mi('Save', Icons.save_outlined, onSave, '$_shortcutMeta+S'),
            _mi('Save All', Icons.save_alt_outlined, onSaveAll,
                '$_shortcutMeta+Shift+S'),
          ]),
          _menuButton(context, 'Edit', [
            _mi('Undo', Icons.undo, () {}, '$_shortcutMeta+Z'),
            _mi('Redo', Icons.redo, () {}, '$_shortcutMeta+Shift+Z'),
          ]),
          _menuButton(context, 'View', [
            _mi('Toggle Sidebar', Icons.view_sidebar_outlined, onToggleSidebar,
                '$_shortcutMeta+B'),
            _mi('Toggle Terminal', Icons.terminal, onToggleTerminal,
                '$_shortcutMeta+`'),
            _mi('Command Palette', Icons.search, onCommandPalette,
                '$_shortcutMeta+Shift+P'),
          ]),
          _menuButton(context, 'Terminal', [
            _mi('New Shell', Icons.add, onToggleTerminal,
                '$_shortcutMeta+Shift+`'),
          ]),
          _menuButton(context, 'Plugins', [
            _mi('Marketplace', Icons.storefront_outlined, onMarketplace, null),
            _mi('Reload Plugins', Icons.refresh, onReloadPlugins, null),
          ]),
          _menuButton(context, 'Tools', [
            _mi('Settings', Icons.settings_outlined, onSettings,
                '$_shortcutMeta+,'),
          ]),
          _menuButton(context, 'Help', [
            _mi('About', Icons.info_outline, onAbout, null),
          ]),
          const Spacer(),
          if (PlatformInfo.isDesktop) _themeToggle(context),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _themeToggle(BuildContext ctx) {
    final settings = ctx.read<SettingsModel>();
    final isDark = settings.themeMode == ThemeMode.dark;
    return InkWell(
      onTap: () => settings.set('theme', isDark ? 'light' : 'dark'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isDark ? Icons.dark_mode : Icons.light_mode,
            size: 12,
            color: VscodeTheme.fgMuted,
          ),
          const SizedBox(width: 4),
          Text(isDark ? 'Dark' : 'Light',
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _menuButton(BuildContext ctx, String title, List<PopupMenuEntry<VoidCallback>> items) {
    return PopupMenuButton<VoidCallback>(
      tooltip: '',
      color: VscodeTheme.bgSidebar,
      offset: const Offset(0, 32),
      itemBuilder: (_) => items,
      onSelected: (cb) => cb(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Text(title,
            style: const TextStyle(
                color: VscodeTheme.fg,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _mi(String label, IconData icon,
      VoidCallback cb, String? shortcut) {
    return PopupMenuItem<VoidCallback>(
      value: cb,
      height: 30,
      child: Row(children: [
        Icon(icon, size: 14, color: VscodeTheme.fgMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 12)),
        ),
        if (shortcut != null)
          Text(shortcut,
              style: const TextStyle(
                  color: VscodeTheme.fgMuted, fontSize: 10)),
      ]),
    );
  }
}

/// Клавиатурные шорткаты для desktop-версии.
class DesktopShortcuts {
  static const save = _SaveIntent();
  static const saveAll = _SaveAllIntent();
  static const toggleTerminal = _ToggleTerminalIntent();
  static const toggleSidebar = _ToggleSidebarIntent();
  static const commandPalette = _CommandPaletteIntent();
  static const settings = _SettingsIntent();

  static Map<ShortcutActivator, Intent> get all {
    return const {
      SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): saveAll,
      SingleActivator(LogicalKeyboardKey.backquote, control: true): toggleTerminal,
      SingleActivator(LogicalKeyboardKey.keyB, control: true): toggleSidebar,
      SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): commandPalette,
      SingleActivator(LogicalKeyboardKey.comma, control: true): settings,
    };
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _SaveAllIntent extends Intent {
  const _SaveAllIntent();
}

class _ToggleTerminalIntent extends Intent {
  const _ToggleTerminalIntent();
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}
