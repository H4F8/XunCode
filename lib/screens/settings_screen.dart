import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';
import '../models/github_user.dart';
import '../models/settings_model.dart';
import '../models/update_model.dart';
import '../services/file_service.dart';
import '../services/github_oauth_service.dart';
import '../services/language_service.dart';
import '../services/platform_info.dart';
import '../services/plugin_runtime.dart';
import '../services/plugin_service.dart';
import '../services/terminal_service.dart';
import '../services/update_service.dart';
import '../widgets/report_problem_sheet.dart';
import '../widgets/update_dialog.dart';
import 'about_screen.dart';
import 'github_signin_screen.dart';
import 'hard_update_screen.dart';
import 'installed_plugins_screen.dart';
import 'languages_screen.dart';
import 'plugin_docs_screen.dart';
import 'user_agreement_screen.dart';

const _editorThemes = <String, String>{
  'XunCode Dark': 'xuncode-dark',
  'Dracula': 'dracula',
  'Monokai': 'monokai',
  'GitHub Dark': 'github-dark',
  'VS Dark': 'vs-dark',
  'VS Light': 'vs',
};

String _editorThemeLabel(String id) => _editorThemes.entries
    .firstWhere((e) => e.value == id, orElse: () => _editorThemes.entries.first)
    .key;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  GithubUser? _githubUser;
  bool _githubLoading = true;
  bool _hasAllFiles = false;
  bool _sharedPublic = false;
  String _sharedPath = '';
  String _privatePath = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadGithub();
    _loadStorage();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final v = await UpdateService.appVersion();
    if (!mounted) return;
    setState(() => _appVersion = v);
  }

  Future<void> _loadStorage() async {
    await FileService.ensureLayout();
    final has = await FileService.hasAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _hasAllFiles = has;
      _sharedPublic = FileService.sharedIsPublic;
      _sharedPath = FileService.sharedRoot;
      _privatePath = FileService.privateRoot;
    });
  }

  Future<void> _grantStorage() async {
    if (!PlatformInfo.needsStoragePermission) {
      // На desktop открываем папку в файловом менеджере ОС.
      await _openSharedFolder();
      return;
    }
    await FileService.requestAllFilesAccess();
    // Re-check after a short delay so the UI updates when the user returns.
    Future.delayed(const Duration(seconds: 1), _loadStorage);
  }

  Future<void> _openSharedFolder() async {
    final path = FileService.sharedRoot;
    final uri = Uri.parse('file://$path');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (PlatformInfo.fileManagerCommand(path) != null) {
      await Process.run(PlatformInfo.fileManagerCommand(path)!, [path],
          runInShell: false);
    }
  }

  Future<void> _loadGithub() async {
    final user = await GithubOAuthService.getUser();
    if (!mounted) return;
    setState(() {
      _githubUser = user;
      _githubLoading = false;
    });
  }

  Future<void> _signIn() async {
    final user = await Navigator.push<GithubUser?>(
      context,
      MaterialPageRoute(builder: (_) => const GithubSignInScreen()),
    );
    if (user != null && mounted) {
      setState(() => _githubUser = user);
    } else {
      _loadGithub();
    }
  }

  Future<void> _signOut() async {
    await GithubOAuthService.signOut();
    if (mounted) setState(() => _githubUser = null);
  }

  Future<void> _openLanguagesFolder() async {
    final lang = LanguageService.of(context, listen: false);
    final path = FileService.languagesDir;
    // Папка должна существовать до открытия.
    try {
      await Directory(path).create(recursive: true);
    } catch (_) {}

    // file:// через url_launcher на Android блокируется — открываем
    // нативно через SAF document URI, при неудаче копируем путь.
    bool opened = false;
    try {
      opened = await const MethodChannel('com.xunkal1.xuncode/update')
              .invokeMethod<bool>('openPath', {'path': path}) ??
          false;
    } catch (_) {}

    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: path));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('settings.language.path_copied',
            params: {'path': path})),
        backgroundColor: VscodeTheme.accent,
      ));
    }
  }

  Future<void> _refreshLanguages() async {
    final lang = LanguageService.of(context, listen: false);
    await lang.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _clearTerminalCache() async {
    final lang = LanguageService.of(context, listen: false);
    await TerminalBridge.clearAlpineCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(lang.tr('terminal.clear_cache_done')),
      backgroundColor: VscodeTheme.accent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsModel>();
    final lang = context.watch<LanguageService>();
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(lang.tr('settings.title')),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          _section(lang.tr('settings.section.appearance')),
          _dropdown(context, lang.tr('settings.theme'),
            s.themeMode == ThemeMode.dark ? 'dark' : 'light',
            const ['dark', 'light'], (v) => s.set('theme', v!)),
          _slider(context, lang.tr('settings.font_size'), s.fontSize, 10, 24,
            (v) => s.set('fontSize', v)),
          _dropdown(context, lang.tr('settings.font_family'), s.fontFamily,
            const ['JetBrains Mono', 'Fira Code', 'Cascadia Code', 'monospace'],
            (v) => s.set('fontFamily', v!)),

          _section(lang.tr('settings.section.editor')),
          _dropdown(context, lang.tr('settings.editor_theme'),
            _editorThemeLabel(s.editorTheme),
            _editorThemes.keys.toList(),
            (v) => s.set('editor.theme', _editorThemes[v] ?? 'xuncode-dark')),
          _dropdown(context, lang.tr('settings.tab_size'), s.tabSize.toString(),
            const ['2', '4', '8'], (v) => s.set('tabSize', int.parse(v!))),
          _toggle(context, lang.tr('settings.word_wrap'), s.wordWrap,
            (v) => s.set('wordWrap', v)),
          _dropdown(context, lang.tr('settings.auto_save'), s.autoSave,
            const ['off', 'afterDelay', 'onFocusChange'],
            (v) => s.set('autoSave', v!)),

          _section(lang.tr('settings.section.completion')),
          _toggle(context, lang.tr('settings.completion.enabled'),
            s.completionEnabled, (v) => s.set('completion.enabled', v)),
          _intSlider(
            context,
            label: lang.tr('settings.completion.delay'),
            value: s.completionDelayMs,
            min: 0,
            max: 500,
            step: 50,
            valueLabel: lang.tr('settings.completion.delay_value',
                params: {'ms': s.completionDelayMs}),
            onChanged: (v) => s.set('completion.delayMs', v),
          ),
          _intSlider(
            context,
            label: lang.tr('settings.completion.max_items'),
            value: s.completionMaxItems,
            min: 10,
            max: 100,
            step: 5,
            valueLabel: '${s.completionMaxItems}',
            onChanged: (v) => s.set('completion.maxItems', v),
          ),

          _section(lang.tr('settings.section.language')),
          ..._buildLanguageOptions(s, lang),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.folder_open, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('settings.language.open_folder'),
                style: const TextStyle(color: VscodeTheme.accent, fontSize: 13)),
            subtitle: Text(
              lang.tr('settings.language.folder_path', params: {'path': FileService.languagesDir}),
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
            ),
            trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.accent),
            onTap: _openLanguagesFolder,
          ),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.refresh, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('settings.language.refresh'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('settings.language.add_hint'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            isThreeLine: true,
            onTap: _refreshLanguages,
          ),

          _section(lang.tr('settings.section.sync')),
          _buildGithubSync(lang),

          _section(lang.tr('settings.section.plugins')),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.code, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('languages.title'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('languages.subtitle'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LanguagesScreen())),
          ),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.extension_outlined, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('settings.plugins.installed'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('settings.plugins.installed_subtitle'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const InstalledPluginsScreen())),
          ),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.menu_book_outlined, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('settings.plugins.docs'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('settings.plugins.docs_subtitle'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PluginDocsScreen())),
          ),

          _section(lang.tr('settings.section.network')),
          _toggle(context, lang.tr('settings.network.tor'), s.torEnabled,
              (v) => s.set('torEnabled', v)),

          _section(lang.tr('settings.section.storage')),
          _buildStorageInfo(lang),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.cleaning_services_outlined,
                size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('terminal.clear_cache'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('terminal.clear_cache_subtitle'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            isThreeLine: true,
            onTap: _clearTerminalCache,
          ),

          _section(lang.tr('settings.section.developer')),
          _toggle(context, lang.tr('settings.developer.mode'), s.developerMode,
              (v) => s.set('developerMode', v)),
          if (s.developerMode) _devModePanel(context, lang),

          _section(lang.tr('settings.section.updates')),
          _buildUpdateTile(context, lang),

          _section(lang.tr('settings.section.about')),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.bug_report_outlined,
                size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('feedback.title'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right,
                size: 16, color: VscodeTheme.fgMuted),
            onTap: () => showReportProblemSheet(context),
          ),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.gavel_outlined,
                size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('legal.title'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right,
                size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserAgreementScreen()),
            ),
          ),
          _info(lang.tr('settings.about.version'),
              _appVersion.isEmpty ? '…' : _appVersion),
          _info(lang.tr('settings.about.platform'), lang.tr('settings.about.platform_value')),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
            title: Text(lang.tr('support.author'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(lang.tr('support.subtitle'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.open_in_new, size: 14, color: Colors.redAccent),
            onTap: () async {
              final uri = Uri.parse('https://www.donationalerts.com/r/wenerking');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          _link(context, 'GitHub: @H4F8', 'https://github.com/H4F8'),
          _link(context, 'Dev channel: t.me/XunKal1Dev', 'https://t.me/XunKal1Dev'),
          _link(context, 'Community: t.me/GodPassTGK', 'https://t.me/GodPassTGK'),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            title: Text(lang.tr('settings.about.about_link'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _buildLanguageOptions(SettingsModel s, LanguageService lang) {
    final tiles = <Widget>[
      RadioListTile<String>(
        value: 'system',
        groupValue: s.language,
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        activeColor: VscodeTheme.accent,
        title: Text(lang.tr('settings.language.system'),
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        onChanged: (v) => _selectLanguage(s, lang, v ?? 'system'),
      ),
    ];
    for (final entry in lang.available) {
      tiles.add(RadioListTile<String>(
        value: entry.code,
        groupValue: s.language,
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        activeColor: VscodeTheme.accent,
        title: Text(entry.displayName,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        subtitle: Text(entry.code,
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
        onChanged: (v) => _selectLanguage(s, lang, v ?? entry.code),
      ));
    }
    return tiles;
  }

  Future<void> _selectLanguage(SettingsModel s, LanguageService lang, String code) async {
    await s.set('language', code);
    await lang.setLanguage(code);
  }

  Widget _buildGithubSync(LanguageService lang) {
    if (_githubLoading) {
      return Container(
        color: VscodeTheme.bgSidebar,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        alignment: Alignment.centerLeft,
        child: const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: VscodeTheme.accent),
        ),
      );
    }
    final user = _githubUser;
    if (user == null) {
      return ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        leading: const Icon(Icons.code, size: 18, color: VscodeTheme.accent),
        title: Text(lang.tr('settings.github.signin'),
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        subtitle: Text(lang.tr('settings.github.signin_subtitle'),
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
        onTap: _signIn,
      );
    }
    return Column(
      children: [
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: user.avatarUrl != null
              ? CircleAvatar(radius: 14, backgroundImage: NetworkImage(user.avatarUrl!))
              : const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
          title: Text('@${user.login}',
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(user.name ?? lang.tr('settings.github.signed_in_subtitle'),
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          trailing: TextButton(
            onPressed: _signOut,
            child: Text(lang.tr('settings.github.signout'),
                style: const TextStyle(color: VscodeTheme.red, fontSize: 12)),
          ),
        ),
        Container(
          color: VscodeTheme.bgSidebar,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          alignment: Alignment.centerLeft,
          child: Text(lang.tr('settings.github.repo_sync_soon'),
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
        ),
      ],
    );
  }

  /// Пункт «Обновление программы»: свежая проверка при клике, диалог с
  /// changelog'ом последнего релиза, красный огонёк пока не просмотрено.
  Widget _buildUpdateTile(BuildContext context, LanguageService lang) {
    final hasBadge = context.watch<UpdateModel>().hasSoftBadge;
    return ListTile(
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
      leading: const Icon(Icons.system_update_alt,
          size: 18, color: VscodeTheme.accent),
      title: Text(lang.tr('settings.updates'),
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      subtitle: Text(lang.tr('settings.updates_subtitle'),
          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
      trailing: hasBadge
          ? Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                shape: BoxShape.circle,
              ),
            )
          : const Icon(Icons.chevron_right,
              size: 16, color: VscodeTheme.fgMuted),
      onTap: () => _openUpdateDialog(context),
    );
  }

  Future<void> _openUpdateDialog(BuildContext context) async {
    final lang = LanguageService.of(context, listen: false);
    // Свежая проверка прямо по клику — офлайн просто покажем ошибку.
    final res = await UpdateService.check();
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('update.check_failed')),
        backgroundColor: VscodeTheme.red,
      ));
      return;
    }
    if (res.hasHardUpdate) {
      // Критический релиз — сразу тотальная блокировка, без диалога.
      final model = context.read<UpdateModel>();
      await model.adopt(res);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
        pageBuilder: (_, __, ___) => HardUpdateScreen(result: res),
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ));
      return;
    }
    if (!res.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('update.up_to_date')),
        backgroundColor: VscodeTheme.accent,
      ));
      await context.read<UpdateModel>().dismissSoft();
      return;
    }
    await UpdateDialog.show(context, res);
    if (!mounted) return;
    // Закрытие диалога любым способом гасит огонёк до следующего релиза.
    await context.read<UpdateModel>().dismissSoft();
  }

  Widget _buildStorageInfo(LanguageService lang) {
    return Column(
      children: [
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: Icon(
            _sharedPublic ? Icons.folder_shared_outlined : Icons.folder_off_outlined,
            size: 18,
            color: _sharedPublic ? VscodeTheme.accent : VscodeTheme.red,
          ),
          title: Text(lang.tr('settings.storage.projects_folder'),
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(
            _sharedPath.isEmpty
                ? lang.tr('settings.storage.resolving')
                : (_sharedPublic
                    ? _sharedPath
                    : '$_sharedPath\n${lang.tr('settings.storage.fallback_warning')}'),
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
          isThreeLine: !_sharedPublic && _sharedPath.isNotEmpty,
        ),
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: const Icon(Icons.lock_outline, size: 18, color: VscodeTheme.fgMuted),
          title: Text(lang.tr('settings.storage.app_data'),
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(
            _privatePath.isEmpty ? lang.tr('settings.storage.resolving') : _privatePath,
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
        ),
        if (!_hasAllFiles)
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.shield_outlined, size: 18, color: VscodeTheme.accent),
            title: Text(lang.tr('settings.storage.grant_access'),
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: Text(
              lang.tr('settings.storage.grant_subtitle'),
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
            ),
            trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.accent),
            onTap: _grantStorage,
          ),
      ],
    );
  }

  Widget _section(String title) => Container(
        color: VscodeTheme.bg,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        alignment: Alignment.centerLeft,
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                color: VscodeTheme.fgLabel,
                letterSpacing: 1,
                fontWeight: FontWeight.w600)),
      );

  Widget _toggle(BuildContext ctx, String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        value: value,
        onChanged: onChanged,
        activeColor: VscodeTheme.accent,
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
      );

  Widget _dropdown(BuildContext ctx, String label, String value,
          List<String> options, ValueChanged<String?> onChanged) =>
      ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        trailing: DropdownButton<String>(
          value: value,
          dropdownColor: VscodeTheme.bgInput,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
          underline: const SizedBox(),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      );

  Widget _slider(BuildContext ctx, String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        title: Text('$label: ${value.round()}px',
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        subtitle: Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          activeColor: VscodeTheme.accent,
          onChanged: onChanged,
          onChangeEnd: onChanged,
        ),
      );

  Widget _intSlider(
    BuildContext ctx, {
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required String valueLabel,
    required ValueChanged<int> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    return ListTile(
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
      title: Text('$label: $valueLabel',
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      subtitle: Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: divisions,
        activeColor: VscodeTheme.accent,
        onChanged: (v) {
          final stepped = (v / step).round() * step;
          onChanged(stepped.clamp(min, max));
        },
      ),
    );
  }

  Widget _info(String label, String value) => ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        trailing: Text(value, style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
      );

  Widget _link(BuildContext ctx, String label, String url) => ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        title: Text(label, style: const TextStyle(color: VscodeTheme.accent, fontSize: 13)),
        trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.accent),
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      );

  Widget _devModePanel(BuildContext ctx, LanguageService lang) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lang.tr('settings.developer.local_install_title'),
              style: const TextStyle(color: VscodeTheme.fgLabel, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            lang.tr('settings.developer.local_install_hint'),
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _installLocalPluginFolder,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(lang.tr('settings.developer.pick_folder')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VscodeTheme.bgInput,
                    foregroundColor: VscodeTheme.fg,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _installFromGithubUrl,
                  icon: const Icon(Icons.cloud_download, size: 16),
                  label: Text(lang.tr('settings.developer.from_url')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VscodeTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _installFromGithubUrl() async {
    final lang = LanguageService.of(context, listen: false);
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VscodeTheme.bgSidebar,
        title: Text(lang.tr('settings.developer.install_from_github'),
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
          decoration: InputDecoration(
            hintText: lang.tr('settings.developer.github_url_hint'),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(lang.tr('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(lang.tr('common.install'),
                style: const TextStyle(color: VscodeTheme.accent)),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final installed = await PluginService.installFromGithub(url);
      await PluginRuntime.instance.activate(installed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('notify.installed', params: {'name': installed.name})),
        backgroundColor: VscodeTheme.accent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('errors.install_failed', params: {'error': e})),
        backgroundColor: VscodeTheme.red,
      ));
    }
  }

  Future<void> _installLocalPluginFolder() async {
    final lang = LanguageService.of(context, listen: false);
    final picked = await FileService.importFolder();
    if (picked == null) return;
    try {
      final installed = await PluginService.installFromLocalFolder(picked);
      await PluginRuntime.instance.activate(installed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('notify.installed', params: {'name': installed.name})),
        backgroundColor: VscodeTheme.accent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('errors.install_failed', params: {'error': e})),
        backgroundColor: VscodeTheme.red,
      ));
    }
  }
}
