import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class EditorBridge {
  final InAppWebViewController _ctrl;
  final String Function() _languageGetter;

  EditorBridge(this._ctrl, this._languageGetter);

  Future<String> getText() async {
    final r = await _ctrl.evaluateJavascript(source: 'window.editor && window.editor.getValue()');
    return r?.toString() ?? '';
  }

  Future<void> setText(String text) async {
    await _ctrl.evaluateJavascript(
      source: 'window.editor && window.editor.setValue(${jsonEncode(text)})',
    );
  }

  Future<String> getSelection() async {
    final r = await _ctrl.evaluateJavascript(source: '''
      (function () {
        if (!window.editor) return '';
        var s = window.editor.getSelection();
        if (!s) return '';
        return window.editor.getModel().getValueInRange(s);
      })()
    ''');
    return r?.toString() ?? '';
  }

  Future<void> setSelection(int startLine, int startCol, int endLine, int endCol) async {
    await _ctrl.evaluateJavascript(source: '''
      window.editor && window.editor.setSelection({
        startLineNumber: $startLine, startColumn: $startCol,
        endLineNumber: $endLine, endColumn: $endCol
      });
    ''');
  }

  Future<void> insertText(String text) async {
    await _ctrl.evaluateJavascript(source: '''
      (function () {
        if (!window.editor) return;
        window.editor.trigger('plugin', 'type', { text: ${jsonEncode(text)} });
      })()
    ''');
  }

  Future<void> replaceRange(int startLine, int startCol, int endLine, int endCol, String text) async {
    await _ctrl.evaluateJavascript(source: '''
      (function () {
        if (!window.editor) return;
        var range = {
          startLineNumber: $startLine, startColumn: $startCol,
          endLineNumber: $endLine, endColumn: $endCol
        };
        window.editor.executeEdits('plugin', [{ range: range, text: ${jsonEncode(text)} }]);
      })()
    ''');
  }

  Future<String> getLine(int line) async {
    final r = await _ctrl.evaluateJavascript(
      source: 'window.editor && window.editor.getModel().getLineContent($line)',
    );
    return r?.toString() ?? '';
  }

  Future<List<String>> getLines() async {
    final r = await _ctrl.evaluateJavascript(
      source: 'window.editor && window.editor.getModel().getLinesContent()',
    );
    if (r is List) return r.map((e) => e?.toString() ?? '').toList();
    return [];
  }

  String getLanguage() => _languageGetter();

  Future<void> setLanguage(String langId) async {
    await _ctrl.evaluateJavascript(source: '''
      (function () {
        if (!window.monaco || !window.editor) return;
        window.monaco.editor.setModelLanguage(window.editor.getModel(), ${jsonEncode(langId)});
      })()
    ''');
  }

  Future<void> formatDocument() async {
    await _ctrl.evaluateJavascript(
      source: "window.editor && window.editor.getAction('editor.action.formatDocument').run()",
    );
  }

  Future<Map<String, int>> getCursorPosition() async {
    final r = await _ctrl.evaluateJavascript(source: '''
      (function () {
        if (!window.editor) return null;
        var p = window.editor.getPosition();
        return p ? { line: p.lineNumber, column: p.column } : null;
      })()
    ''');
    if (r is Map) {
      return {
        'line': (r['line'] is num) ? (r['line'] as num).toInt() : 1,
        'column': (r['column'] is num) ? (r['column'] as num).toInt() : 1,
      };
    }
    return {'line': 1, 'column': 1};
  }

  Future<void> setCursorPosition(int line, int column) async {
    await _ctrl.evaluateJavascript(source: '''
      window.editor && window.editor.setPosition({ lineNumber: $line, column: $column });
    ''');
  }

  Future<void> executeCommand(String command) async {
    await _ctrl.evaluateJavascript(
      source: 'window.editor && window.editor.trigger("plugin", ${jsonEncode(command)}, null)',
    );
  }

  void dispose() {
    // Контроллер WebView освобождается внешне (EditorScreen.dispose).
  }
}
