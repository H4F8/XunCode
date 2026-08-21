import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import '../services/file_service.dart';
import '../services/language_service.dart';
import 'file_tree.dart';
import 'report_problem_sheet.dart';

/// Стартовый экран редактора: пока не открыт ни один файл,
/// вместо полотна Monaco показывается меню — недавние файлы и дерево
/// папки Projects. Брендинг строго XunCode: название текстом, без фото.
class EditorHome extends StatefulWidget {
  final void Function(String path, String name, String content) onOpenFile;
  final Future<void> Function() onImportFile;

  const EditorHome({
    super.key,
    required this.onOpenFile,
    required this.onImportFile,
  });

  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _RecentRef {
  final String path;
  final String name;
  const _RecentRef(this.path, this.name);
}

/// Список недавних файлов (SharedPreferences, JSON). Отдельно от виджета,
/// чтобы editor_screen мог фиксировать открытия независимо от того,
/// показан домашний экран или редактор.
class RecentFiles {
  static const _recentKey = 'editor.recentFiles';

  static Future<List<_RecentRef>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_recentKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => _RecentRef(
              m['path']?.toString() ?? '', m['name']?.toString() ?? ''))
          .where((r) => r.path.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> push(String path, String name) async {
    if (path.isEmpty) return;
    final list = [
      _RecentRef(path, name),
      ...(await load()).where((r) => r.path != path),
    ].take(12).toList();
    await _persist(list);
  }

  static Future<void> remove(String path) async {
    await _persist((await load()).where((r) => r.path != path).toList());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
  }

  static Future<void> _persist(List<_RecentRef> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentKey,
        jsonEncode(list.map((r) => {'path': r.path, 'name': r.name}).toList()));
  }
}

class _EditorHomeState extends State<EditorHome> {
  List<FileNode>? _tree;
  List<_RecentRef> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final recent = await RecentFiles.load();

    List<FileNode> tree = const [];
    try {
      await FileService.ensureLayout();
      tree = await FileService.buildTree(FileService.projectsDir);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _recent = recent;
      _tree = tree;
      _loading = false;
    });
  }

  Future<void> _clearRecent() async {
    await RecentFiles.clear();
    if (mounted) setState(() => _recent = const []);
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Шапка: имя приложения текстом, никакого фото/логотипа ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 14),
          color: VscodeTheme.bgSidebar,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('XunCode',
                        style: TextStyle(
                            color: VscodeTheme.fg,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                    SizedBox(height: 3),
                    Text(lang.tr('home.subtitle'),
                        style: TextStyle(
                            color: VscodeTheme.fgMuted, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: lang.tr('home.import'),
                icon: Icon(Icons.folder_open,
                    size: 20, color: VscodeTheme.accent),
                onPressed: () async {
                  await widget.onImportFile();
                  _reload();
                },
              ),
              IconButton(
                tooltip: lang.tr('common.refresh'),
                icon: Icon(Icons.refresh,
                    size: 20, color: VscodeTheme.fgMuted),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : ListView(
                  children: [
                    // ── Баннер ранней стадии разработки ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: VscodeTheme.bgInput,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.55)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.construction,
                                  size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(lang.tr('home.dev_banner_title'),
                                  style: const TextStyle(
                                    color: VscodeTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600))),
                            ]),
                            const SizedBox(height: 6),
                            Text(lang.tr('home.dev_banner_text'),
                              style: const TextStyle(
                                color: VscodeTheme.fgMuted, fontSize: 12)),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.bug_report_outlined,
                                  size: 14, color: VscodeTheme.accent),
                                label: Text(lang.tr('feedback.title'),
                                  style: const TextStyle(fontSize: 12)),
                                onPressed: () =>
                                    showReportProblemSheet(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_recent.isNotEmpty) ...[
                      _SectionHeader(
                          title: lang.tr('home.recent'),
                          onClear: _clearRecent),
                      ..._recent.map((r) => ListTile(
                            dense: true,
                            leading: Icon(Icons.history,
                                size: 16, color: VscodeTheme.fgMuted),
                            title: Text(r.name,
                                style: TextStyle(
                                    color: VscodeTheme.fg, fontSize: 13)),
                            subtitle: Text(r.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: VscodeTheme.fgMuted, fontSize: 10)),
                            onTap: () => _openByPath(r),
                          )),
                    ],
                    _SectionHeader(title: lang.tr('home.files')),
                    if (_tree == null || _tree!.isEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, 18, 24, 18),
                        child: Text(lang.tr('home.empty_tree'),
                            style: TextStyle(
                                color: VscodeTheme.fgMuted, fontSize: 12)),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: FileTreeWidget(
                          nodes: _tree!,
                          onFileTap: (n) => _openNode(n),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _openNode(FileNode n) async {
    if (n.isDir) return;
    final f = await FileService.readFile(n.path);
    if (f != null && mounted) {
      widget.onOpenFile(f['path'] ?? n.path, f['name'] ?? n.name,
          f['content'] ?? '');
    }
  }

  Future<void> _openByPath(_RecentRef r) async {
    final f = await FileService.readFile(r.path);
    if (f != null && mounted) {
      widget.onOpenFile(f['path'] ?? r.path, f['name'] ?? r.name,
          f['content'] ?? '');
    } else if (mounted) {
      // Файл удалён — убираем из недавних.
      await RecentFiles.remove(r.path);
      if (mounted) setState(() => _recent = _recent.where((x) => x.path != r.path).toList());
    }
  }
}

/// Заголовок секции домашнего экрана.
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onClear;
  const _SectionHeader({required this.title, this.onClear});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                color: VscodeTheme.fgLabel,
                letterSpacing: 1,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        if (onClear != null)
          IconButton(
              icon: const Icon(Icons.clear_all,
                  size: 16, color: VscodeTheme.fgMuted),
              onPressed: onClear),
      ]),
    );
  }
}
