import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';

/// Компактный встроенный рендерер Markdown для changelog'ов релизов.
///
/// Поддерживает то, что реально пишут в GitHub Releases: заголовки,
/// жирный/курсив, инлайн-код, блоки кода, списки, цитаты, ссылки
/// и горизонтальные разделители. Без внешних зависимостей.
class MarkdownText extends StatefulWidget {
  final String data;
  final double baseFontSize;

  const MarkdownText(this.data, {super.key, this.baseFontSize = 13.5});

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final _linkRecognizers = <TapGestureRecognizer>[];

  static final _inline = RegExp(
    r'\*\*(.+?)\*\*' // **bold**
    r'|\*(.+?)\*' // *italic*
    r'|`([^`]+)`' // `code`
    r'|\[([^\]]+)\]\(([^)\s]+)\)', // [text](url)
  );

  @override
  void dispose() {
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.data.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++; // закрывающая ```
        if (buf.isNotEmpty) blocks.add(_codeBlock(buf.join('\n')));
        continue;
      }

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          height: 1,
          color: VscodeTheme.border,
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('#### ')) {
        blocks.add(_header(trimmed.substring(5), 13));
        i++;
        continue;
      }
      if (trimmed.startsWith('### ')) {
        blocks.add(_header(trimmed.substring(4), 14));
        i++;
        continue;
      }
      if (trimmed.startsWith('## ')) {
        blocks.add(_header(trimmed.substring(3), 16));
        i++;
        continue;
      }
      if (trimmed.startsWith('# ')) {
        blocks.add(_header(trimmed.substring(2), 18));
        i++;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        final buf = <String>[trimmed.substring(2)];
        i++;
        while (i < lines.length && lines[i].trim().startsWith('> ')) {
          buf.add(lines[i].trim().substring(2));
          i++;
        }
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: VscodeTheme.accent, width: 3)),
          ),
          child: _paragraph(buf.join('\n'), italic: true),
        ));
        continue;
      }

      final bullet = RegExp(r'^[-*+]\s+(.*)').firstMatch(trimmed);
      if (bullet != null) {
        blocks.add(_listItem('\u2022', bullet.group(1)!));
        i++;
        continue;
      }

      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)').firstMatch(trimmed);
      if (numbered != null) {
        blocks.add(_listItem('${numbered.group(1)}.', numbered.group(2)!));
        i++;
        continue;
      }

      // Обычный абзац; соседние строки склеиваем как в Markdown.
      final buf = <String>[trimmed];
      i++;
      while (i < lines.length) {
        final next = lines[i].trim();
        if (next.isEmpty ||
            next.startsWith('#') ||
            next.startsWith('>') ||
            next.startsWith('```') ||
            next == '---' ||
            RegExp(r'^[-*+]\s+').hasMatch(next) ||
            RegExp(r'^\d+[.)]\s+').hasMatch(next)) {
          break;
        }
        buf.add(next);
        i++;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _paragraph(buf.join('\n')),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _header(String text, double size) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            color: VscodeTheme.fg,
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      );

  Widget _listItem(String marker, String body) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text(marker,
                  style: const TextStyle(
                      color: VscodeTheme.accent, fontSize: 13, height: 1.35)),
            ),
            Expanded(child: _paragraph(body)),
          ],
        ),
      );

  Widget _paragraph(String text, {bool italic = false}) => SelectableText.rich(
        TextSpan(
          children: _inlineSpans(text),
          style: TextStyle(
            color: VscodeTheme.fg,
            fontSize: widget.baseFontSize,
            height: 1.35,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );

  Widget _codeBlock(String code) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: VscodeTheme.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            code,
            style: const TextStyle(
              color: VscodeTheme.fgString,
              fontSize: 12.5,
              height: 1.4,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      );

  List<InlineSpan> _inlineSpans(String text) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(3),
          style: const TextStyle(
            color: VscodeTheme.fgString,
            fontFamily: 'JetBrains Mono',
            fontSize: 12.5,
          ),
        ));
      } else if (m.group(4) != null && m.group(5) != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openUrl(m.group(5)!);
        _linkRecognizers.add(recognizer);
        spans.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(
            color: VscodeTheme.accent,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
