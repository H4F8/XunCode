import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/open_file.dart';
import '../models/settings_model.dart';
import '../models/update_model.dart';
import '../services/completion_service.dart';
import '../services/file_service.dart';
import '../services/language_service.dart';
import '../services/platform_info.dart';
import '../services/tor_service.dart';
import '../services/plugin_runtime.dart';
import '../services/editor_bridge.dart';
import '../widgets/activity_bar.dart';
import '../widgets/command_palette.dart';
import '../widgets/desktop_menu.dart';
import '../widgets/editor_home.dart';
import '../widgets/sidebar.dart';
import '../widgets/tab_bar.dart';
import '../widgets/status_bar.dart';
import '../widgets/terminal_panel.dart';
import 'about_screen.dart';
import 'settings_screen.dart';
import 'marketplace_screen.dart';

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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const double _kTabletBreakpoint = 600;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webCtrl;
  EditorBridge? _editorBridge;
  ActivityBarItem _activeBar = ActivityBarItem.explorer;
  bool _sidebarVisible = true;
  bool _terminalVisible = false;
  String _currentLang = 'plaintext';
  int _line = 1, _col = 1;
  bool _torEnabled = false;

  @override
  void initState() {
    super.initState();
    TorService.checkStatus().then((v) {
      if (mounted) setState(() => _torEnabled = v);
    });
  }

  @override
  void dispose() {
    PluginRuntime.instance.detachUi();
    _editorBridge?.dispose();
    _webCtrl?.dispose();
    super.dispose();
  }

  void _onActivityBarSelect(ActivityBarItem item) {
    if (item == ActivityBarItem.settings) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    if (item == ActivityBarItem.extensions) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplaceScreen()));
      return;
    }
    setState(() {
      if (_activeBar == item) {
        _sidebarVisible = !_sidebarVisible;
      } else {
        _activeBar = item;
        _sidebarVisible = true;
      }
    });
  }

  void _openFile(String path, String name, String content) {
    final filesModel = context.read<OpenFilesModel>();
    filesModel.open(OpenFile(uri: path, name: name, content: content));
    unawaited(RecentFiles.push(path, name));
    _loadInEditor(content, name);
    PluginRuntime.instance.fireFileOpen(path);
    _maybeIndexProject(path);
    final width = MediaQuery.of(context).size.width;
    if (width < _kTabletBreakpoint) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      _scaffoldKey.currentState?.closeDrawer();
      setState(() => _sidebarVisible = false);
    }
  }

  void _maybeIndexProject(String filePath) {
    // Index the projects root once per project. CompletionService is
    // idempotent — repeated calls with the same root are cheap.
    try {
      final root = FileService.projectsDir;
      if (CompletionService.instance.projectRoot != root) {
        unawaited(CompletionService.instance.indexProject(root));
      }
    } catch (_) {}
  }

  void _loadInEditor(String content, String name) {
    final lang = _detectLang(name);
    setState(() => _currentLang = lang);
    _webCtrl?.evaluateJavascript(
      source: 'window.loadFile(${jsonEncode(content)}, ${jsonEncode(lang)}, ${jsonEncode(name)});',
    );
  }

  bool _saving = false;

  Future<void> _saveActive() async {
    if (_saving) return; // не даём автосохранению копиться очередью при наборе
    _saving = true;
    try {
      final filesModel = context.read<OpenFilesModel>();
      final active = filesModel.active;
      if (active == null) return;
      final result = await _webCtrl?.evaluateJavascript(source: 'window.editor.getValue()');
      if (result == null) return;
      final content = result is String ? result : result.toString();
      await FileService.saveFile(active.uri, content);
      filesModel.markClean(active.uri);
      PluginRuntime.instance.fireSave(active.uri);
    } finally {
      _saving = false;
    }
  }

  Future<void> _toggleTor() async {
    if (_torEnabled) {
      await TorService.stop();
    } else {
      await TorService.start();
    }
    final status = await TorService.checkStatus();
    if (mounted) setState(() => _torEnabled = status);
  }

  void _toggleTerminal() => setState(() => _terminalVisible = !_terminalVisible);

  @override
  Widget build(BuildContext context) {
    final filesModel = context.watch<OpenFilesModel>();
    final settings = context.watch<SettingsModel>();

    return Shortcuts(
      shortcuts: PlatformInfo.isDesktop ? DesktopShortcuts.all : const {},
      child: Actions(
        actions: PlatformInfo.isDesktop
            ? {
                _SaveIntent: CallbackAction<_SaveIntent>(
                  onInvoke: (_) {
                    _saveActive();
                    return null;
                  },
                ),
                _SaveAllIntent: CallbackAction<_SaveAllIntent>(
                  onInvoke: (_) {
                    _saveActive();
                    return null;
                  },
                ),
                _ToggleTerminalIntent: CallbackAction<_ToggleTerminalIntent>(
                  onInvoke: (_) {
                    _toggleTerminal();
                    return null;
                  },
                ),
                _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
                  onInvoke: (_) {
                    setState(() => _sidebarVisible = !_sidebarVisible);
                    return null;
                  },
                ),
                _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
                  onInvoke: (_) {
                    showPluginCommandPalette(context);
                    return null;
                  },
                ),
                _SettingsIntent: CallbackAction<_SettingsIntent>(
                  onInvoke: (_) {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    return null;
                  },
                ),
              }
            : {},
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final isTablet = constraints.maxWidth >= _kTabletBreakpoint ||
                  PlatformInfo.isDesktop;
              return Scaffold(
                key: _scaffoldKey,
                backgroundColor: VscodeTheme.bg,
                resizeToAvoidBottomInset: true,
                drawer: isTablet || PlatformInfo.isDesktop
                    ? null
                    : _PhoneDrawer(
                        activePanel: _activeBar.name,
                        filesModel: filesModel,
                        onFileOpen: _openFile,
                      ),
                body: SafeArea(
                  child: filesModel.active == null
                      // Как в Acode: без открытых файлов показываем меню,
                      // а не полотно редактора.
                      ? EditorHome(
                          onOpenFile: _openFile,
                          onImportFile: _pickAndOpenFile,
                        )
                      : Column(
                    children: [
                      if (PlatformInfo.isDesktop)
                        DesktopMenuBar(
                          onNewProject: () {},
                          onOpenFile: _pickAndOpenFile,
                          onOpenFolder: _pickAndOpenFolder,
                          onSave: _saveActive,
                          onSaveAll: _saveActive,
                          onToggleSidebar: () =>
                              setState(() => _sidebarVisible = !_sidebarVisible),
                          onToggleTerminal: _toggleTerminal,
                          onCommandPalette: () => showPluginCommandPalette(context),
                          onSettings: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen())),
                          onMarketplace: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MarketplaceScreen())),
                          onAbout: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AboutScreen())),
                          onReloadPlugins: () => PluginRuntime.instance.reloadAll(),
                        ),
                      Expanded(
                        child: isTablet
                            ? _buildTabletLayout(filesModel, settings)
                            : _buildPhoneLayout(filesModel, settings),
                      ),
                      if (PlatformInfo.isDesktop) _buildDesktopStatusStrip(),
                    ],
                  ),
                ),
                bottomNavigationBar: isTablet || PlatformInfo.isDesktop
                    ? null
                    : _buildPhoneNav(),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndOpenFile() async {
    final f = await FileService.importFile();
    if (f != null) _openFile(f['path']!, f['name']!, f['content']!);
  }

  Future<void> _pickAndOpenFolder() async {
    final path = await FileService.importFolder();
    if (path != null && mounted) {
      final dir = Directory(path);
      if (await dir.exists()) {
        // Project root switching is a future enhancement; currently we just
        // expose the folder via the file picker.
      }
    }
  }

  Widget _buildDesktopStatusStrip() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: VscodeTheme.statusBg,
        border: Border(top: BorderSide(color: Color(0xFF005A99))),
      ),
      child: Row(children: [
        Icon(
          PlatformInfo.isLinux
              ? Icons.laptop
              : PlatformInfo.isMacOS
                  ? Icons.laptop_mac
                  : Icons.computer,
          color: Colors.white,
          size: 12,
        ),
        const SizedBox(width: 6),
        const Text('XunCode',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(PlatformInfo.label,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  Widget _buildTabletLayout(OpenFilesModel filesModel, SettingsModel settings) {
    final isLandscape = MediaQuery.of(context).size.width >
        MediaQuery.of(context).size.height;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              ActivityBar(selected: _activeBar, onSelect: _onActivityBarSelect,
                  settingsBadge: context.watch<UpdateModel>().hasSoftBadge),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        EditorTabBar(model: filesModel),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _buildEditor(settings)),
                              if (_terminalVisible)
                                SizedBox(
                                  height: 280,
                                  child: TerminalPanel(
                                    onClose: _toggleTerminal,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_sidebarVisible)
                      Positioned(
                        left: 0, top: 0, bottom: 0,
                        child: Row(
                          children: [
                            Sidebar(
                              activePanel: _activeBar.name,
                              filesModel: filesModel,
                              onFileOpen: _openFile,
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _sidebarVisible = false),
                              child: Container(
                                width: isLandscape ? 40 : 0,
                                color: Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      right: 12, bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'tablet-cmd',
                            backgroundColor: VscodeTheme.bgInput,
                            foregroundColor: VscodeTheme.accent,
                            tooltip: LanguageService.of(context).tr('editor.plugin_commands'),
                            onPressed: () => showPluginCommandPalette(context),
                            child: const Icon(Icons.bolt_outlined, size: 18),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'tablet-term',
                            backgroundColor: VscodeTheme.bgInput,
                            foregroundColor: VscodeTheme.accent,
                            tooltip: LanguageService.of(context).tr('editor.toggle_terminal'),
                            onPressed: _toggleTerminal,
                            child: const Icon(Icons.terminal, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VscodeStatusBar(
          fileName: filesModel.active?.name ?? '',
          language: _currentLang,
          line: _line,
          col: _col,
          torEnabled: _torEnabled,
          onTorTap: _toggleTor,
          onLangTap: () {},
        ),
      ],
    );
  }

  Widget _buildPhoneLayout(OpenFilesModel filesModel, SettingsModel settings) {
    return Column(
      children: [
        EditorTabBar(model: filesModel),
        Expanded(
          child: Stack(
            children: [
              _buildEditor(settings),
              Positioned(
                right: 12, bottom: 24,
                child: FloatingActionButton.small(
                  heroTag: 'phone-cmd',
                  backgroundColor: VscodeTheme.bgInput,
                  foregroundColor: VscodeTheme.accent,
                  tooltip: LanguageService.of(context).tr('editor.plugin_commands'),
                  onPressed: () => showPluginCommandPalette(context),
                  child: const Icon(Icons.bolt_outlined, size: 16),
                ),
              ),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (d) {
                    if ((d.primaryDelta ?? 0) < -8 && !_terminalVisible) {
                      _openTerminalSheet();
                    }
                  },
                  child: Container(
                    height: 14,
                    alignment: Alignment.center,
                    child: Container(
                      width: 36, height: 3,
                      decoration: BoxDecoration(
                        color: VscodeTheme.fgMuted.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        VscodeStatusBar(
          fileName: filesModel.active?.name ?? '',
          language: _currentLang,
          line: _line,
          col: _col,
          torEnabled: _torEnabled,
          onTorTap: _toggleTor,
          onLangTap: () {},
        ),
      ],
    );
  }

  Widget _buildPhoneNav() {
    final lang = LanguageService.of(context);
    final hasUpdateBadge = context.watch<UpdateModel>().hasSoftBadge;
    return BottomNavigationBar(
      backgroundColor: VscodeTheme.bgSidebar,
      selectedItemColor: VscodeTheme.accent,
      unselectedItemColor: VscodeTheme.fgMuted,
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      onTap: (i) {
        switch (i) {
          case 0:
            setState(() => _activeBar = ActivityBarItem.explorer);
            _scaffoldKey.currentState?.openDrawer();
            break;
          case 1:
            setState(() => _activeBar = ActivityBarItem.search);
            _scaffoldKey.currentState?.openDrawer();
            break;
          case 2:
            _openTerminalSheet();
            break;
          case 3:
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MarketplaceScreen()));
            break;
          case 4:
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
            break;
        }
      },
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.folder_outlined, size: 20), label: lang.tr('nav.files')),
        BottomNavigationBarItem(icon: const Icon(Icons.search, size: 20), label: lang.tr('nav.search')),
        BottomNavigationBarItem(icon: const Icon(Icons.terminal, size: 20), label: lang.tr('nav.terminal')),
        BottomNavigationBarItem(icon: const Icon(Icons.extension_outlined, size: 20), label: lang.tr('nav.plugins')),
        BottomNavigationBarItem(
            icon: _settingsNavIcon(hasUpdateBadge), label: lang.tr('nav.settings')),
      ],
    );
  }

  /// Шестерёнка с красным огоньком, когда доступно обновление.
  Widget _settingsNavIcon(bool badge) {
    final icon = const Icon(Icons.settings_outlined, size: 20);
    if (!badge) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -5,
          top: -2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  void _openTerminalSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VscodeTheme.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.25,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, __) => TerminalPanel(
            onClose: () => Navigator.maybePop(sheetCtx),
          ),
        );
      },
    );
  }

  Widget _buildEditor(SettingsModel settings) {
    return RepaintBoundary(
      child: InAppWebView(
        initialFile: 'assets/editor.html',
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          supportZoom: false,
          transparentBackground: true,
          cacheEnabled: true,
          cacheMode: CacheMode.LOAD_DEFAULT,
          // ВАЖНО: useHybridComposition НЕ включать — в этом режиме у
          // inappwebview клавиатура перестаёт открываться по тапу.
        ),
        onWebViewCreated: (ctrl) {
          _webCtrl = ctrl;
          _editorBridge = EditorBridge(ctrl, () => _currentLang);
          _registerHandlers(ctrl, settings);
        },
        onLoadStop: (ctrl, _) async {
          await _applySettings(settings);
          if (_editorBridge != null) {
            PluginRuntime.instance.attachEditor(_editorBridge!);
            PluginRuntime.instance.attachUi((msg, {bool isError = false}) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg),
                backgroundColor: isError ? VscodeTheme.red : VscodeTheme.accent,
              ));
            });
            PluginRuntime.instance.attachOpenFile((path) async {
              final r = await FileService.readFile(path);
              if (r != null && mounted) {
                _openFile(r['path']!, r['name']!, r['content']!);
              }
            });
            PluginRuntime.instance.attachInputBox((title, placeholder, value) async {
              if (!mounted) return null;
              return _showPluginInputBox(title, placeholder, value);
            });
            PluginRuntime.instance.attachQuickPick((items, title) async {
              if (!mounted) return null;
              return _showPluginQuickPick(items, title);
            });
            unawaited(PluginRuntime.instance.activateInstalled());
          }
        },
      ),
    );
  }

  void _registerHandlers(InAppWebViewController ctrl, SettingsModel settings) {
    ctrl.addJavaScriptHandler(
      handlerName: 'onCursorChange',
      callback: (args) {
        if (!mounted) return;
        if (args.length >= 2) {
          final line = args[0] is int ? args[0] : (args[0] as num).toInt();
          final col = args[1] is int ? args[1] : (args[1] as num).toInt();
          setState(() {
            _line = line;
            _col = col;
          });
          PluginRuntime.instance.fireCursorMove(line, col);
        }
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'onSelectionChange',
      callback: (_) {},
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'onContentChange',
      callback: (args) {
        final filesModel = context.read<OpenFilesModel>();
        final active = filesModel.active;
        if (active != null) filesModel.markDirty(active.uri);
        PluginRuntime.instance.fireEditorChange(
          args.isNotEmpty ? args[0]?.toString() ?? '' : '',
        );
        if (settings.autoSave == 'afterDelay') {
          Future.delayed(const Duration(seconds: 1), _saveActive);
        }
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'saveFile',
      callback: (args) async {
        if (args.length < 2) return;
        await FileService.saveFile(args[0], args[1]);
        if (mounted) context.read<OpenFilesModel>().markClean(args[0]);
        PluginRuntime.instance.fireSave(args[0]);
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'getCompletions',
      callback: (args) async {
        if (!settings.completionEnabled) return const [];
        final params = args.isNotEmpty && args.first is Map
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        final lang = (params['language'] ?? 'plaintext').toString();
        final prefix = (params['prefix'] ?? '').toString();
        final path = (params['path'] ?? '').toString();
        final maxItems = params['maxItems'] is num
            ? (params['maxItems'] as num).toInt()
            : settings.completionMaxItems;
        try {
          final items = await CompletionService.instance.suggest(
            language: lang,
            prefix: prefix,
            currentFilePath: path.isEmpty ? null : path,
            maxItems: maxItems,
          );
          return items;
        } catch (_) {
          return const [];
        }
      },
    );
  }

  Future<void> _applySettings(SettingsModel s) async {
    final payload = jsonEncode({
      'fontSize': s.fontSize,
      'fontFamily': s.fontFamily,
      'tabSize': s.tabSize,
      'wordWrap': s.wordWrap ? 'on' : 'off',
      'theme': s.editorTheme,
    });
    await _webCtrl?.evaluateJavascript(source: 'window.applySettings && window.applySettings($payload);');
    final completionPayload = jsonEncode({
      'enabled': s.completionEnabled,
      'delayMs': s.completionDelayMs,
      'maxItems': s.completionMaxItems,
    });
    await _webCtrl?.evaluateJavascript(
      source: 'window.applyCompletionSettings && window.applyCompletionSettings($completionPayload);',
    );
  }

  Future<String?> _showPluginInputBox(String? title, String? placeholder, String? value) {
    final ctrl = TextEditingController(text: value ?? '');
    final lang = LanguageService.of(context, listen: false);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VscodeTheme.bgSidebar,
        title: Text(title ?? lang.tr('editor.input'),
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
          decoration: InputDecoration(
            hintText: placeholder ?? '',
            hintStyle: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: Text(lang.tr('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(lang.tr('common.ok'), style: const TextStyle(color: VscodeTheme.accent)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showPluginQuickPick(List<String> items, String? title) {
    final lang = LanguageService.of(context, listen: false);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: VscodeTheme.bgSidebar,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null && title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title.toUpperCase(),
                    style: const TextStyle(color: VscodeTheme.fgLabel,
                      fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600)),
                ),
              ),
            ...items.map((it) => ListTile(
                  dense: true,
                  title: Text(it, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
                  onTap: () => Navigator.pop(context, it),
                )),
            ListTile(
              dense: true,
              leading: const Icon(Icons.close, size: 16, color: VscodeTheme.fgMuted),
              title: Text(lang.tr('common.cancel'),
                  style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
              onTap: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }

  String _detectLang(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'js': 'javascript', 'ts': 'typescript', 'jsx': 'javascript', 'tsx': 'typescript',
      'mjs': 'javascript', 'cjs': 'javascript',
      'py': 'python', 'kt': 'kotlin', 'kts': 'kotlin',
      'java': 'java', 'dart': 'dart', 'go': 'go',
      'rs': 'rust', 'c': 'c', 'cpp': 'cpp', 'h': 'cpp', 'hpp': 'cpp', 'cs': 'csharp',
      'html': 'html', 'htm': 'html', 'css': 'css', 'scss': 'scss', 'sass': 'sass',
      'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown', 'sh': 'shell',
      'bash': 'shell', 'zsh': 'shell', 'fish': 'shell',
      'xml': 'xml', 'php': 'php', 'rb': 'ruby', 'swift': 'swift',
      'sql': 'sql', 'r': 'r', 'lua': 'lua', 'dockerfile': 'dockerfile',
      'makefile': 'makefile', 'cmake': 'cmake', 'ini': 'ini', 'toml': 'toml',
      'vue': 'vue', 'svelte': 'svelte',
    };
    return map[ext] ?? 'plaintext';
  }
}

class _PhoneDrawer extends StatelessWidget {
  final String activePanel;
  final OpenFilesModel filesModel;
  final void Function(String path, String name, String content) onFileOpen;

  const _PhoneDrawer({
    required this.activePanel,
    required this.filesModel,
    required this.onFileOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: VscodeTheme.bgSidebar,
      width: 280,
      child: SafeArea(
        child: Sidebar(
          activePanel: activePanel,
          filesModel: filesModel,
          onFileOpen: (path, name, content) {
            onFileOpen(path, name, content);
          },
        ),
      ),
    );
  }
}
