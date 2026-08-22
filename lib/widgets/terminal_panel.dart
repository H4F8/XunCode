import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app/theme.dart';
import '../services/language_service.dart';
import '../services/terminal_service.dart';

/// Вкладка терминала: живая PTY-сессия + буфер вывода, накопленный пока
/// вкладка была неактивна.
class TermTab {
  final String id;
  final String name;
  final TerminalSession session;
  final StringBuffer back = StringBuffer();
  StreamSubscription<String>? sub;

  /// Терминал подключён к AXS напрямую из WebView (AttachAddon),
  /// как в AcodeX — Dart-мост вывода для этой вкладки не используется.
  bool attachedToWs = false;

  TermTab({required this.id, required this.name, required this.session});

  void appendBack(String chunk) {
    back.write(chunk);
    // Ограничиваем буфер, чтобы долгие сессии не съедали память.
    if (back.length > 300000) {
      final s = back.toString().substring(back.length ~/ 2);
      back
        ..clear()
        ..write(s);
    }
  }

  void dispose() {
    sub?.cancel();
  }
}

/// Реестр сессий, переживающий закрытие панели: терминал продолжает жить
/// в фоне, как в Acode. Умирает только по явному «×» на вкладке.
class TerminalStore {
  static final List<TermTab> tabs = [];
  static int active = -1;
  static bool booted = false;
}

/// Панель терминала: настоящий эмулятор xterm.js в WebView, вкладки,
/// перетаскиваемый верхний край. Данные гоняются через Dart-мост:
/// WS-сессии держит [TerminalBridge], эмулятор получает байты через JS API.
class TerminalPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final double? minHeight;
  final ValueChanged<double>? onHeightDrag;

  const TerminalPanel({
    super.key,
    this.onClose,
    this.minHeight,
    this.onHeightDrag,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  InAppWebViewController? _web;
  bool _pageReady = false;
  bool _installing = false;
  String _installStage = '';
  double _installProgress = 0;
  String? _installError;
  CancelToken? _cancelToken;

  // Батчинг вывода: копим и льём в xterm раз в 16 мс.
  final StringBuffer _pending = StringBuffer();
  Timer? _flushTimer;
  String? _pendingTabId;

  List<TermTab> get _tabs => TerminalStore.tabs;
  int get _active => TerminalStore.active;

  @override
  void initState() {
    super.initState();
    _bootstrapIfNeeded();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    for (final t in _tabs) {
      t.sub?.cancel();
      t.sub = null;
    }
    super.dispose();
  }

  Future<void> _bootstrapIfNeeded() async {
    if (TerminalStore.booted) return;
    TerminalStore.booted = true;
    final installed = await TerminalBridge.isAlpineInstalled();
    if (!installed) {
      // Сначала дожидаемся установки rootfs (прогресс уже на экране),
      // и только потом открываем сессию.
      final ok = await _installAlpine();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    if (_tabs.isEmpty) await _newTab();
  }

  /// Возвращает true при успешной установке.
  Future<bool> _installAlpine() async {
    final cancelToken = CancelToken();
    setState(() {
      _installing = true;
      _installStage = 'Preparing';
      _installProgress = 0;
      _installError = null;
      _cancelToken = cancelToken;
    });
    try {
      await TerminalBridge.installAlpine(
        cancelToken: cancelToken,
        onProgress: (p, stage) {
          if (!mounted) return;
          setState(() {
            _installProgress = p;
            _installStage = stage;
          });
        },
      );
    } catch (e) {
      if (!mounted) return false;
      if (cancelToken.isCancelled) {
        setState(() =>
            _installError = LanguageService.of(context).tr('terminal.cancelled'));
      } else {
        setState(() => _installError = 'Install failed: $e');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _cancelToken = null;
        });
      }
    }
    return true;
  }

  void _cancelInstall() => _cancelToken?.cancel('user cancelled');

  Future<void> _newTab({bool unsandboxed = false}) async {
    final id = 'term-${DateTime.now().microsecondsSinceEpoch}';
    TerminalSession session;
    try {
      session = unsandboxed
          ? await TerminalBridge.createUnsandboxed(id: id)
          : await TerminalBridge.create(id: id);
    } catch (e) {
      if (mounted) setState(() => _installError = '$e');
      return;
    }
    final tab = TermTab(id: id, name: 'sh ${_tabs.length + 1}', session: session);
    tab.sub = session.output.listen((chunk) => _route(tab, chunk));
    setState(() => _tabs.add(tab));
    await _activate(_tabs.length - 1);
    await _attachDirectIfPossible(tab);
  }

  /// Прямое подключение эмулятора к AXS (архитектура AcodeX):
  /// ввод/вывод через WebSocket прямо в WebView, минуя Dart-мост.
  Future<void> _attachDirectIfPossible(TermTab tab) async {
    final s = tab.session;
    final port = s.axsPort;
    final pid = s.remotePid;
    if (!_pageReady || _web == null) return;
    if (port == null || port <= 0 || pid == null || pid.isEmpty) return;
    try {
      await _web!.evaluateJavascript(
        source:
            "termApi.attach('${tab.id}', $port, '$pid', ${s.cols}, ${s.rows});",
      );
      tab.attachedToWs = true;
    } catch (_) {}
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final removed = _tabs[index];
    await removed.session.kill().catchError((_) {});
    removed.dispose();
    setState(() {
      _tabs.removeAt(index);
      if (_active == index) {
        TerminalStore.active =
            _tabs.isEmpty ? -1 : (_active >= _tabs.length ? _tabs.length - 1 : _active);
      } else if (_active > index) {
        TerminalStore.active = _active - 1;
      }
    });
    _web?.evaluateJavascript(source: "termApi.closeTerm('${removed.id}')");
    if (_active >= 0) {
      await _showTab(_tabs[_active]);
    }
  }

  Future<void> _activate(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    // Сначала сливаем незаконченный батч прежней активной вкладки в её буфер.
    _flushTimer?.cancel();
    if (_pending.isNotEmpty && _pendingTabId != null) {
      final t = _tabs.where((x) => x.id == _pendingTabId).firstOrNull;
      t?.appendBack(_pending.toString());
      _pending.clear();
    }
    setState(() => TerminalStore.active = index);
    await _showTab(_tabs[index]);
  }

  /// Реплей буфера + показ вкладки в эмуляторе.
  Future<void> _showTab(TermTab tab) async {
    if (!_pageReady || _web == null) return;
    if (tab.back.isNotEmpty) {
      final text = tab.back.toString();
      tab.back.clear();
      // Кусками, чтобы не упереться в лимит evaluateJavascript.
      for (var i = 0; i < text.length; i += 60000) {
        final end = (i + 60000).clamp(0, text.length);
        await _web!.evaluateJavascript(
          source: 'termApi.write(${jsonEncode(text.substring(i, end))});',
        );
      }
    }
    await _web!.evaluateJavascript(source: "termApi.show('${tab.id}');");
  }

  void _route(TermTab tab, String chunk) {
    if (!mounted || tab.attachedToWs) return; // вывод уже идёт напрямую по WS

    if (tab.id != _tabs.elementAtOrNull(_active)?.id) {
      tab.appendBack(chunk);
      return;
    }
    if (!_pageReady) {
      tab.appendBack(chunk);
      return;
    }
    if (_pendingTabId != null && _pendingTabId != tab.id) {
      // Не успели слить прежний батч — уводим в его буфер.
      final prev = _tabs.where((x) => x.id == _pendingTabId).firstOrNull;
      prev?.appendBack(_pending.toString());
      _pending.clear();
    }
    _pendingTabId = tab.id;
    _pending.write(chunk);
    _flushTimer ??= Timer(const Duration(milliseconds: 16), _flushPending);
  }

  Future<void> _flushPending() async {
    _flushTimer = null;
    if (_pending.isEmpty || _web == null || !_pageReady) return;
    final data = _pending.toString();
    _pending.clear();
    try {
      await _web!.evaluateJavascript(
        source: 'termApi.write(${jsonEncode(data)});',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: widget.minHeight ?? 200),
      decoration: const BoxDecoration(
        color: VscodeTheme.bgPanel,
        border: Border(top: BorderSide(color: VscodeTheme.border)),
      ),
      child: Column(
        children: [
          if (widget.onHeightDrag != null) _buildDragHandle(),
          _buildHeader(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => widget.onHeightDrag?.call(d.delta.dy),
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: VscodeTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final lang = LanguageService.of(context);
    final collapsed = _tabs.isEmpty;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: VscodeTheme.bgTab,
        border: Border(bottom: BorderSide(color: VscodeTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 14, color: VscodeTheme.fgMuted),
          const SizedBox(width: 6),
          Text(lang.tr('terminal.title'),
            style: const TextStyle(fontSize: 11, color: VscodeTheme.fgLabel,
              letterSpacing: 1, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(
            child: collapsed
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 2),
                    itemBuilder: (_, i) {
                      final selected = i == _active;
                      return InkWell(
                        onTap: () => _activate(i),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? VscodeTheme.bgPanel
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: selected
                                  ? VscodeTheme.accent
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_tabs[i].name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? VscodeTheme.fg
                                      : VscodeTheme.fgMuted,
                                )),
                              const SizedBox(width: 5),
                              InkWell(
                                onTap: () => _closeTab(i),
                                child: const Icon(Icons.close,
                                  size: 12, color: VscodeTheme.fgMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: VscodeTheme.fgMuted,
            tooltip: lang.tr('terminal.new_shell'),
            onPressed: _installing ? null : () => _newTab(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            color: VscodeTheme.fgMuted,
            tooltip: lang.tr('terminal.hide'),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_installing) return _buildInstaller();
    if (_installError != null) return _buildError();
    if (_tabs.isEmpty) {
      final lang = LanguageService.of(context);
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 14),
          label: Text(lang.tr('terminal.new_shell'),
              style: const TextStyle(fontSize: 12)),
          onPressed: () => _newTab(),
        ),
      );
    }
    return InAppWebView(
      initialFile: 'assets/terminal/terminal.html',
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        supportZoom: false,
        transparentBackground: true,
        cacheEnabled: false,
        disableContextMenu: true,
        // ВАЖНО: useHybridComposition НЕ включать — в этом режиме у
        // inappwebview клавиатура перестаёт открываться по тапу.
      ),
      onWebViewCreated: (ctrl) {
        _web = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'termData',
          callback: (args) {
            if (args.isEmpty || args[0] is! String) return null;
            final tab = _tabs.elementAtOrNull(_active);
            tab?.session.write(args[0] as String);
            return null;
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'termResize',
          callback: (args) {
            if (args.length < 2) return null;
            final cols = args[0] is int ? args[0] : (args[0] as num).toInt();
            final rows = args[1] is int ? args[1] : (args[1] as num).toInt();
            final tab = _tabs.elementAtOrNull(_active);
            tab?.session.resize(cols, rows);
            return null;
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'termReady',
          callback: (args) {
            _pageReady = true;
            _replayAll();
            return null;
          },
        );
      },
      onLoadStop: (_, __) => _refit(),
    );
  }

  /// После (пере)создания WebView восстанавливаем все вкладки.
  Future<void> _replayAll() async {
    if (!_pageReady || _web == null) return;
    for (final t in _tabs) {
      await _web!.evaluateJavascript(
        source: "termApi.create('${t.id}', 80, 24);",
      );
    }
    for (final t in _tabs) {
      await _attachDirectIfPossible(t);
    }
    final legacyActive =
        _active >= 0 && _active < _tabs.length && !_tabs[_active].attachedToWs;
    if (legacyActive) {
      await _showTab(_tabs[_active]);
    }
  }

  Future<void> _refit() async {
    await _web?.evaluateJavascript(source: 'termApi.refitAll();');
  }

  Widget _buildInstaller() {
    final lang = LanguageService.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_download_outlined, size: 36, color: VscodeTheme.accent),
          const SizedBox(height: 12),
          Text(_installStage,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _installProgress > 0 ? _installProgress : null,
            color: VscodeTheme.accent,
            backgroundColor: VscodeTheme.bgInput,
            minHeight: 3,
          ),
          const SizedBox(height: 6),
          Text(lang.tr('terminal.alpine_size'),
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          const SizedBox(height: 10),
          if (_cancelToken != null)
            TextButton.icon(
              icon: const Icon(Icons.cancel, size: 14),
              label: Text(lang.tr('terminal.cancel')),
              style: TextButton.styleFrom(foregroundColor: VscodeTheme.fgMuted),
              onPressed: _cancelInstall,
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final lang = LanguageService.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 32, color: VscodeTheme.red),
          const SizedBox(height: 10),
          Text(_installError ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Alpine Linux rootfs is required for the terminal.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: Text(lang.tr('common.retry')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VscodeTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  setState(() => _installError = null);
                  TerminalStore.booted = false;
                  _bootstrapIfNeeded();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal, size: 14),
                label: Text(lang.tr('terminal.use_limited_shell')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VscodeTheme.fgMuted,
                  side: const BorderSide(color: VscodeTheme.border),
                ),
                onPressed: () {
                  setState(() => _installError = null);
                  _newTab(unsandboxed: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
