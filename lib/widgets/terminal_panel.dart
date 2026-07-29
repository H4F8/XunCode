import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/language_service.dart';
import '../services/terminal_service.dart';

/// Embedded terminal panel ÄËĂÂĂÂ multi-tab proot+Alpine shells. Designed to be
/// dropped under the editor on tablets, or pulled up as a draggable sheet on
/// phones (see editor_screen.dart ÄÂĂÂ§3 / ÄÂĂÂ§4).
class TerminalPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final double? minHeight;
  const TerminalPanel({super.key, this.onClose, this.minHeight});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> with TickerProviderStateMixin {
  final List<_Tab> _tabs = [];
  late TabController _ctrl;
  bool _installing = false;
  String _installStage = '';
  double _installProgress = 0;
  String? _installError;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _ctrl = TabController(length: 0, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final installed = await TerminalBridge.isAlpineInstalled();
    if (!installed) {
      // Если rootfs встроен в APK — распаковываем его и сразу открываем Alpine.
      // Иначе открываем ограниченный shell параллельно с загрузкой.
      if (await TerminalBridge.hasEmbeddedRootfs()) {
        _installAlpine();
        await _newTab();
      } else {
        await _newTab(unsandboxed: true);
        _installAlpine();
      }
      return;
    }
    await _newTab();
  }

  Future<void> _installAlpine() async {
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
      if (!mounted) return;
      if (cancelToken.isCancelled) {
        final lang = LanguageService.of(context);
        setState(() => _installError = lang.tr('terminal.cancelled'));
      } else {
        setState(() => _installError = 'Install failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _cancelToken = null;
        });
      }
    }
  }

  void _cancelInstall() {
    _cancelToken?.cancel('user cancelled');
  }

  Future<void> _newTab({bool unsandboxed = false}) async {
    final id = 'term-${DateTime.now().microsecondsSinceEpoch}';
    final session = unsandboxed
        ? await TerminalBridge.createUnsandboxed(id: id)
        : await TerminalBridge.create(id: id);
    final tab = _Tab(session: session);
    setState(() {
      _tabs.add(tab);
      _ctrl.dispose();
      _ctrl = TabController(length: _tabs.length, vsync: this, initialIndex: _tabs.length - 1);
    });
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final removed = _tabs.removeAt(index);
    await removed.session.kill();
    removed.dispose();
    final newLen = _tabs.length;
    final newIdx = newLen == 0 ? 0 : (index >= newLen ? newLen - 1 : index);
    setState(() {
      _ctrl.dispose();
      _ctrl = TabController(length: newLen, vsync: this, initialIndex: newIdx);
    });
    if (newLen == 0 && widget.onClose != null) widget.onClose!();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.session.kill();
      t.dispose();
    }
    _ctrl.dispose();
    super.dispose();
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
          _buildHeader(),
          if (_installing) _buildInstaller(),
          if (_installError != null) _buildError(),
          if (!_installing && _installError == null) Expanded(child: _buildTabs()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final lang = LanguageService.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          const SizedBox(width: 12),
          if (_tabs.isNotEmpty)
            Expanded(
              child: TabBar(
                controller: _ctrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: VscodeTheme.accent,
                indicatorWeight: 1,
                labelColor: VscodeTheme.fg,
                unselectedLabelColor: VscodeTheme.fgMuted,
                labelStyle: const TextStyle(fontSize: 11),
                tabs: List.generate(_tabs.length, (i) {
                  return Tab(
                    height: 28,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('sh ${i + 1}'),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _closeTab(i),
                          child: const Icon(Icons.close, size: 12, color: VscodeTheme.fgMuted),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            )
          else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: VscodeTheme.fgMuted,
            tooltip: lang.tr('terminal.new_shell'),
            onPressed: _installing ? null : () => _newTab(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (widget.onClose != null)
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
            'Alpine Linux rootfs is required for the terminal. It will be downloaded once (~3 MB).',
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
                  _bootstrap();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal, size: 14),
                label: Text(lang.tr('terminal.use_limited_shell')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VscodeTheme.fgMuted,
                  side: const BorderSide(color: VscodeTheme.border),
                ),
                onPressed: () async {
                  setState(() => _installError = null);
                  await _newTab(unsandboxed: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final lang = LanguageService.of(context);
    if (_tabs.isEmpty) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 14),
          label: Text(lang.tr('terminal.new_shell'),
              style: const TextStyle(fontSize: 12)),
          onPressed: () => _newTab(),
        ),
      );
    }
    return TabBarView(
      controller: _ctrl,
      physics: const NeverScrollableScrollPhysics(),
      children: _tabs.map((t) => _TerminalView(tab: t)).toList(),
    );
  }
}

class _Tab {
  final TerminalSession session;
  final ScrollController scroll = ScrollController();
  final TextEditingController input = TextEditingController();
  final FocusNode focus = FocusNode();
  final ValueNotifier<String> buffer = ValueNotifier('');
  StreamSubscription? sub;
  final StringBuffer _pending = StringBuffer();
  Timer? _flushTimer;
  static final _ansiExp = RegExp(
    r'\x1B\[[0-9;?]*[ -/]*[@-~]'
    r'|\x1B\][^\x07]*\x07'
    r'|\x1B[()][AB012]',
  );

  _Tab({required this.session}) {
    sub = session.output.listen(_onChunk);
  }

  void _onChunk(String chunk) {
    _pending.write(chunk);
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 50), _flushBuffer);
  }

  void _flushBuffer() {
    if (_pending.isEmpty) return;
    final text = _pending.toString()
        .replaceAll(_ansiExp, '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    _pending.clear();
    buffer.value = buffer.value + text;
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushBuffer();
    sub?.cancel();
    scroll.dispose();
    input.dispose();
    focus.dispose();
    buffer.dispose();
  }
}

class _TerminalView extends StatefulWidget {
  final _Tab tab;
  const _TerminalView({required this.tab});

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  bool _ctrlMod = false;
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    widget.tab.buffer.addListener(_scrollToBottom);
    widget.tab.scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.tab.buffer.removeListener(_scrollToBottom);
    widget.tab.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.tab.scroll.hasClients) return;
    final pos = widget.tab.scroll.position;
    _userScrolledUp = pos.pixels < pos.maxScrollExtent - 40;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.tab.scroll.hasClients) return;
      if (_userScrolledUp) return;
      final max = widget.tab.scroll.position.maxScrollExtent;
      widget.tab.scroll.animateTo(
        max,
        duration: Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  void _send(String text) {
    widget.tab.session.write(text);
  }

  Future<void> _submit() async {
    final cmd = widget.tab.input.text;
    widget.tab.input.clear();
    _send('$cmd\n');
    widget.tab.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: widget.tab.buffer,
            builder: (_, text, __) => SingleChildScrollView(
              controller: widget.tab.scroll,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                text.isEmpty ? '' : text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: VscodeTheme.fg,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        _buildKeyRow(),
        _buildPrompt(),
      ],
    );
  }

  Widget _buildKeyRow() {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: VscodeTheme.bgTab,
        border: Border(top: BorderSide(color: VscodeTheme.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _modKey('Ctrl', _ctrlMod, () => setState(() => _ctrlMod = !_ctrlMod)),
          _key('Esc', () => _send('')),
          _key('Tab', () => _send('\t')),
          _key('ÄËĂÂĂÂ', () => _send('[A')),
          _key('ÄËĂÂĂÂ', () => _send('[B')),
          _key('ÄËĂÂĂÂ', () => _send('[D')),
          _key('ÄËĂÂĂÂ', () => _send('[C')),
          _key('|', () => _send('|')),
          _key('~', () => _send('~')),
          _key('/', () => _send('/')),
        ],
      ),
    );
  }

  Widget _modKey(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? VscodeTheme.accent : VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: TextStyle(
            color: active ? Colors.white : VscodeTheme.fg,
            fontSize: 11,
          )),
      ),
    ),
  );

  Widget _key(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 11)),
      ),
    ),
  );

  Widget _buildPrompt() {
    final lang = LanguageService.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: VscodeTheme.bgPanel,
        border: Border(top: BorderSide(color: VscodeTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('\$',
            style: TextStyle(color: VscodeTheme.green, fontFamily: 'monospace', fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: widget.tab.input,
              focusNode: widget.tab.focus,
              autofocus: false,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              style: const TextStyle(
                color: VscodeTheme.fg, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                border: InputBorder.none,
                hintText: lang.tr('terminal.type_command'),
                hintStyle: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              onChanged: _ctrlMod ? _handleCtrl : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 16, color: VscodeTheme.accent),
            onPressed: _submit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  void _handleCtrl(String value) {
    if (value.isEmpty) return;
    final last = value.codeUnitAt(value.length - 1);
    if (last >= 0x40 && last <= 0x7E) {
      final code = last & 0x1F;
      widget.tab.session.write(String.fromCharCode(code));
      widget.tab.input.clear();
      setState(() => _ctrlMod = false);
    }
  }
}
