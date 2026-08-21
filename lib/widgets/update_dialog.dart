import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../models/update_model.dart';
import '../services/language_service.dart';
import '../services/update_service.dart';
import 'markdown_text.dart';

/// Диалог «Доступна новая версия!» для мягкого обновления.
///
/// Показывает Markdown-описание последнего релиза и кнопки «Обновить» /
/// «Позже». Закрытие любым способом гасит красный огонёк.
class UpdateDialog extends StatelessWidget {
  final UpdateCheckResult result;

  const UpdateDialog({super.key, required this.result});

  static Future<void> show(BuildContext context, UpdateCheckResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChangeNotifierProvider<UpdateModel>.value(
        value: context.read<UpdateModel>(),
        child: UpdateDialog(result: result),
      ),
    );
  }

  Future<void> _update(BuildContext context) async {
    final navigator = Navigator.of(context);
    final lang = LanguageService.of(context, listen: false);
    var launched = false;
    try {
      if (result.platform == InstallPlatform.rustore) {
        const channel = MethodChannel('com.xunkal1.xuncode/update');
        final ok = await channel.invokeMethod<bool>('openRustoreAppPage');
        if (ok != true) throw Exception('RuStore not available');
      } else {
        final release = result.latest!;
        var url = release.downloadUrlFor(result.platform);
        if (url.isEmpty) url = release.htmlUrl;
        final uri = Uri.parse(url);
        if (!await canLaunchUrl(uri)) throw Exception('cannot launch $url');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      launched = true;
    } catch (_) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (!launched) {
        navigator.pop();
        messenger?.showSnackBar(SnackBar(
          content: Text(lang.tr('update.error_launch')),
          backgroundColor: VscodeTheme.red,
        ));
        return;
      }
    }
    await context.read<UpdateModel>().dismissSoft();
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final latest = result.latest;
    return AlertDialog(
      backgroundColor: VscodeTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Row(
        children: [
          const Icon(Icons.system_update_alt,
              size: 20, color: VscodeTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lang.tr('update.title'),
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 320,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: VscodeTheme.bgInput,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${latest?.name.isNotEmpty == true ? latest!.name : latest?.tagName ?? ''} '
                  '${lang.tr('update.current', params: {'version': result.currentVersion})}',
                  style: const TextStyle(
                      color: VscodeTheme.fgMuted, fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 12),
              MarkdownText(latest?.body ?? ''),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await context.read<UpdateModel>().dismissSoft();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(lang.tr('update.later'),
              style: const TextStyle(color: VscodeTheme.fgMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: VscodeTheme.accent,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.download, size: 16),
          label: Text(lang.tr('update.update')),
          onPressed: () => _update(context),
        ),
      ],
    );
  }
}
