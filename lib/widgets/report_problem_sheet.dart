import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../services/feedback_service.dart';
import '../services/language_service.dart';

/// Шторка «Сообщить о проблеме». Две вкладки:
///  1. Разработчику — форма через Telegram Bot API;
///  2. На маркет — открыть страницу приложения в магазине для отзыва.
Future<void> showReportProblemSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: VscodeTheme.bgPanel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (sheetCtx) => const _ReportSheet(),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

enum _SendState { idle, sending, sent, failed }

class _ReportSheetState extends State<_ReportSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _ctrl = TextEditingController();
  String _category = 'bug';
  _SendState _state = _SendState.idle;

  @override
  void dispose() {
    _tabs.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _state = _SendState.sending);
    final lang = LanguageService.of(context, listen: false);
    final category = lang.tr('feedback.category_$_category');
    final ok = await FeedbackService.send(
      category: category,
      text: _ctrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _state = ok ? _SendState.sent : _SendState.failed);
  }

  Future<void> _openMarket() async {
    const channel = MethodChannel('com.xunkal1.xuncode/update');
    try {
      final ok = await channel.invokeMethod<bool>('openRustoreAppPage');
      if (ok == true || !mounted) return;
    } catch (_) {}
    if (!mounted) return;
    // Фолбэк: копируем ссылку на страницу приложения.
    await Clipboard.setData(const ClipboardData(
      text: 'https://www.rustore.ru/catalog/app/com.xunkal1.xuncode',
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(LanguageService.of(context).tr('feedback.link_copied')),
      backgroundColor: VscodeTheme.accent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabs,
              indicatorColor: VscodeTheme.accent,
              labelColor: VscodeTheme.fg,
              unselectedLabelColor: VscodeTheme.fgMuted,
              labelStyle: const TextStyle(fontSize: 13),
              tabs: [
                Tab(text: lang.tr('feedback.tab_dev')),
                Tab(text: lang.tr('feedback.tab_market')),
              ],
            ),
            const Divider(height: 1, color: VscodeTheme.border),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildDevForm(lang),
                  _buildMarketTab(lang),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Вкладка 1: форма разработчику ─────────────────────────────────

  Widget _buildDevForm(LanguageService lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              _chip('bug', lang.tr('feedback.category_bug')),
              _chip('idea', lang.tr('feedback.category_idea')),
              _chip('other', lang.tr('feedback.category_other')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 6,
            maxLength: 2000,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: VscodeTheme.bgInput,
              hintText: lang.tr('feedback.hint'),
              hintStyle:
                  const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 12),
          switch (_state) {
            _SendState.sent => _resultRow(Icons.check_circle,
                lang.tr('feedback.sent'), color: Colors.green),
            _SendState.failed => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _resultRow(Icons.error_outline,
                      lang.tr('feedback.failed'), color: VscodeTheme.red),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 14),
                    label: Text(lang.tr('feedback.copy')),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _ctrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(lang.tr('feedback.copied')),
                        backgroundColor: VscodeTheme.accent,
                      ));
                    },
                  ),
                ]),
            _ => FilledButton.icon(
                icon: _state == _SendState.sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 14),
                label: Text(_state == _SendState.sending
                    ? lang.tr('feedback.sending')
                    : lang.tr('feedback.send')),
                style: FilledButton.styleFrom(
                  backgroundColor: VscodeTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    (_state == _SendState.sending || _ctrl.text.trim().isEmpty)
                        ? null
                        : _send,
              ),
          },
          if (!FeedbackService.configured && _state == _SendState.idle) ...[
            const SizedBox(height: 8),
            Text(lang.tr('feedback.not_configured'),
              style: const TextStyle(
                  color: VscodeTheme.fgMuted, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  // ── Вкладка 2: маркет ─────────────────────────────────────────────

  Widget _buildMarketTab(LanguageService lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.storefront_outlined,
              size: 40, color: VscodeTheme.accent),
          const SizedBox(height: 12),
          Text(lang.tr('feedback.market_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 13)),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.store, size: 16),
            label: Text(lang.tr('feedback.open_market')),
            style: FilledButton.styleFrom(
              backgroundColor: VscodeTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _openMarket,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: Text(lang.tr('feedback.copy_review')),
            style: OutlinedButton.styleFrom(
              foregroundColor: VscodeTheme.fgMuted,
              side: const BorderSide(color: VscodeTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _ctrl.text.trim()));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(lang.tr('feedback.copied')),
                backgroundColor: VscodeTheme.accent,
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _category == value;
    return ChoiceChip(
      label: Text(label,
        style: TextStyle(fontSize: 12,
          color: selected ? Colors.white : VscodeTheme.fgMuted)),
      selected: selected,
      onSelected: (_) => setState(() => _category = value),
      selectedColor: VscodeTheme.accent,
      backgroundColor: VscodeTheme.bgInput,
      side: BorderSide.none,
    );
  }

  Widget _resultRow(IconData icon, String text, {required Color color}) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
        style: TextStyle(color: VscodeTheme.fg, fontSize: 13))),
    ]);
  }
}
