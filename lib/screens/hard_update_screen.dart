import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../services/language_service.dart';
import '../services/update_service.dart';
import '../widgets/markdown_text.dart';

/// Экран тотальной блокировки (Hard Update).
///
/// Перекрывает весь IDE непрозрачным слоем: редактор, терминал и файлы
/// физически недоступны. Кнопка «Назад» закрывает приложение целиком —
/// пройти внутрь без обновления невозможно.
class HardUpdateScreen extends StatelessWidget {
  final UpdateCheckResult result;

  const HardUpdateScreen({super.key, required this.result});

  Future<void> _update(BuildContext context) async {
    final lang = LanguageService.of(context, listen: false);
    try {
      if (result.platform == InstallPlatform.rustore) {
        // Открываем страницу XunCode внутри приложения RuStore.
        const channel = MethodChannel('com.xunkal1.xuncode/update');
        final ok = await channel.invokeMethod<bool>('openRustoreAppPage');
        if (ok != true) throw Exception('RuStore not available');
        return;
      }
      final release = result.latest;
      var url = release == null ? '' : release.downloadUrlFor(result.platform);
      if (url.isEmpty && release != null) url = release.htmlUrl;
      if (url.isEmpty) throw Exception('no download url');
      final uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) throw Exception('cannot launch $url');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang.tr('update.error_launch')),
        backgroundColor: VscodeTheme.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // «Назад» намертво закрывает приложение.
        SystemNavigator.pop();
        exit(0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0E0E),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: Icon(Icons.gpp_bad_outlined,
                                size: 72, color: VscodeTheme.red),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              lang.tr('update.hard_title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: VscodeTheme.red,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              lang.tr('update.hard_subtitle', params: {
                                'version': result.currentVersion,
                              }),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: VscodeTheme.fgMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: VscodeTheme.bgSidebar,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: VscodeTheme.red.withValues(alpha: 0.4)),
                            ),
                            child: MarkdownText(result.hardMarkdown),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: VscodeTheme.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.system_update_alt, size: 20),
                    label: Text(
                      lang.tr('update.update_now'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _update(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
