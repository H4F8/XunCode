import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/language_service.dart';

class VscodeStatusBar extends StatelessWidget {
  final String fileName;
  final String language;
  final int line;
  final int col;
  final VoidCallback onLangTap;

  const VscodeStatusBar({
    super.key,
    required this.fileName,
    required this.language,
    required this.line,
    required this.col,
    required this.onLangTap,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      height: 22,
      color: VscodeTheme.statusBg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Flexible(
            child: _item(
                fileName.isEmpty ? lang.tr('app.no_file_open') : fileName,
                () {},
                ellipsis: true),
          ),
          const Spacer(),
          _item(
              lang.tr('status.line_col', params: {'line': line, 'col': col}),
              () {}),
          const SizedBox(width: 8),
          _item(language, onLangTap),
          const SizedBox(width: 8),
          _item(lang.tr('status.encoding'), () {}),
        ],
      ),
    );
  }

  Widget _item(String label, VoidCallback onTap,
      {IconData? icon, Color? iconColor, bool ellipsis = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: iconColor ?? Colors.white),
              const SizedBox(width: 3),
            ],
            ellipsis
                ? Flexible(child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis))
                : Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
