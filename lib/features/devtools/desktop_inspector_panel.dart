import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../browser/engine/browser_engine.dart';
import 'devtools_models.dart';

/// Docked Desktop-style Browser DevTools (`Inspect`) panel sitting cleanly below
/// the live webpage so you can pick elements on the page, edit HTML/CSS, run
/// Console JavaScript, inspect Network + Blocked Ad/Redirect requests, and view
/// Storage & Runtime metrics in real time.
class DesktopInspectorPanel extends StatefulWidget {
  const DesktopInspectorPanel({
    super.key,
    required this.engine,
    required this.onClose,
  });

  final BrowserEngine engine;
  final VoidCallback onClose;

  @override
  State<DesktopInspectorPanel> createState() => _DesktopInspectorPanelState();
}

class _DesktopInspectorPanelState extends State<DesktopInspectorPanel> {
  int _selectedTabIndex = 0; // 0: Elements, 1: Console, 2: Network, 3: Storage, 4: Info
  double _heightFraction = 0.48;

  final TextEditingController _consoleInputCtrl = TextEditingController();
  List<DevToolsDomNode> _domNodes = <DevToolsDomNode>[];
  List<DevToolsNetworkEntry> _netEntries = <DevToolsNetworkEntry>[];
  Map<String, Object?> _storageAndInfo = <String, Object?>{};
  String _netFilter = 'all';
  bool _loadingTab = false;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngineChanged);
    unawaited(_refreshCurrentTab());
  }

  @override
  void didUpdateWidget(covariant DesktopInspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_onEngineChanged);
      widget.engine.addListener(_onEngineChanged);
      unawaited(_refreshCurrentTab());
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChanged);
    unawaited(widget.engine.clearInspectorHighlight(notify: false));
    _consoleInputCtrl.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    if (widget.engine.inspectedElement != null && _selectedTabIndex != 0) {
      setState(() => _selectedTabIndex = 0);
    } else {
      setState(() {});
    }
  }

  Future<void> _refreshCurrentTab() async {
    if (!mounted) return;
    setState(() => _loadingTab = true);
    if (_selectedTabIndex == 0) {
      final List<DevToolsDomNode> nodes = await widget.engine
          .fetchDomTreeNodes();
      if (mounted) setState(() => _domNodes = nodes);
    } else if (_selectedTabIndex == 2) {
      final List<DevToolsNetworkEntry> net = await widget.engine
          .refreshNetworkResourceTimings();
      if (mounted) setState(() => _netEntries = net);
    } else if (_selectedTabIndex == 3 || _selectedTabIndex == 4) {
      final Map<String, Object?> snap = await widget.engine
          .fetchStorageAndMetrics();
      if (mounted) setState(() => _storageAndInfo = snap);
    }
    if (mounted) setState(() => _loadingTab = false);
  }

  void _selectTab(int idx) {
    setState(() => _selectedTabIndex = idx);
    unawaited(_refreshCurrentTab());
  }

  Future<void> _showEditNodeDialog(DevToolsInspectedElement el) async {
    final TextEditingController htmlCtrl = TextEditingController(
      text: el.outerHtml,
    );
    final TextEditingController styleCtrl = TextEditingController(
      text: el.inlineStyle,
    );

    final ({String mode, String val})? result =
        await showDialog<({String mode, String val})>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('Edit <${el.tag}>'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: styleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Inline CSS style="..."',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: htmlCtrl,
                    maxLines: 6,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'outerHTML',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, (mode: 'style', val: styleCtrl.text)),
                child: const Text('Apply Style'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, (mode: 'html', val: htmlCtrl.text)),
                child: const Text('Apply HTML'),
              ),
            ],
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      htmlCtrl.dispose();
      styleCtrl.dispose();
    });

    if (result != null) {
      await widget.engine.mutateDomNode(
        nodeId: el.nodeId,
        action: result.mode,
        value: result.val,
      );
      await _refreshCurrentTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenH = MediaQuery.sizeOf(context).height;
    final double panelHeight = (screenH * _heightFraction).clamp(
      210.0,
      screenH * 0.80,
    );
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool pickerActive = widget.engine.isElementPickerActive;
    final int errCount = widget.engine.consoleErrorCount;

    return Material(
      key: const Key('desktop_inspector_panel'),
      elevation: 16,
      color: const Color(0xFF0B1220),
      child: SizedBox(
        height: panelHeight,
        child: Column(
          children: <Widget>[
            // Top resize handle + Desktop DevTools toolbar
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (DragUpdateDetails d) {
                setState(() {
                  _heightFraction =
                      (_heightFraction - (d.delta.dy / screenH)).clamp(
                        0.32,
                        0.82,
                      );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF111C33),
                  border: Border(
                    top: BorderSide(
                      color: colors.primary.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    // Element Picker button (just like Chrome DevTools top-left cursor icon!)
                    IconButton(
                      key: const Key('devtools_element_picker_button'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 28,
                      ),
                      tooltip: 'Select an element in the page to inspect it',
                      onPressed: () {
                        widget.engine.setElementPickerActive(!pickerActive);
                      },
                      icon: Icon(
                        Icons.ads_click_rounded,
                        size: 17,
                        color: pickerActive
                            ? AppTheme.electricBlue
                            : Colors.white70,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            _DevTabChip(
                              label: 'Elements',
                              active: _selectedTabIndex == 0,
                              onTap: () => _selectTab(0),
                            ),
                            _DevTabChip(
                              label: errCount > 0
                                  ? 'Console ($errCount)'
                                  : 'Console',
                              active: _selectedTabIndex == 1,
                              badgeError: errCount > 0,
                              onTap: () => _selectTab(1),
                            ),
                            _DevTabChip(
                              label: 'Network',
                              active: _selectedTabIndex == 2,
                              onTap: () => _selectTab(2),
                            ),
                            _DevTabChip(
                              label: 'Storage',
                              active: _selectedTabIndex == 3,
                              onTap: () => _selectTab(3),
                            ),
                            _DevTabChip(
                              label: 'Info',
                              active: _selectedTabIndex == 4,
                              onTap: () => _selectTab(4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 28,
                      ),
                      tooltip: 'Refresh DevTools',
                      onPressed: _refreshCurrentTab,
                      icon: const Icon(
                        Icons.sync_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                    IconButton(
                      key: const Key('devtools_close_button'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 28,
                      ),
                      tooltip: 'Close DevTools',
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (pickerActive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                color: AppTheme.electricBlue.withValues(alpha: 0.22),
                child: const Text(
                  'Tap any element on the webpage above to inspect its HTML & CSS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_loadingTab) const LinearProgressIndicator(minHeight: 1.5),
            Expanded(
              child: DefaultTextStyle(
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                child: switch (_selectedTabIndex) {
                  0 => _buildElementsTab(),
                  1 => _buildConsoleTab(),
                  2 => _buildNetworkTab(),
                  3 => _buildStorageTab(),
                  _ => _buildInfoTab(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementsTab() {
    final DevToolsInspectedElement? sel = widget.engine.inspectedElement;

    return Column(
      children: <Widget>[
        if (sel != null)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF13203B),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${sel.selector}  •  ${sel.dimensions}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF60A5FA),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    _MiniActionBtn(
                      label: 'Edit',
                      onTap: () => _showEditNodeDialog(sel),
                    ),
                    const SizedBox(width: 4),
                    _MiniActionBtn(
                      label: 'Hide',
                      onTap: () => widget.engine.mutateDomNode(
                        nodeId: sel.nodeId,
                        action: 'hide',
                      ),
                    ),
                    const SizedBox(width: 4),
                    _MiniActionBtn(
                      label: 'Delete',
                      danger: true,
                      onTap: () async {
                        await widget.engine.mutateDomNode(
                          nodeId: sel.nodeId,
                          action: 'remove',
                        );
                        await _refreshCurrentTab();
                      },
                    ),
                    const SizedBox(width: 4),
                    _MiniActionBtn(
                      label: 'Copy',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: sel.outerHtml));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  sel.outerHtml.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF93C5FD),
                  ),
                ),
                const SizedBox(height: 5),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final MapEntry<String, String> e
                          in sel.computedStyles.entries)
                        if (e.value.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '${e.key}: ${e.value};',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: Color(0xFFA7F3D0),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _domNodes.isEmpty
              ? Center(
                  child: Text(
                    widget.engine.isShowingStartPage
                        ? 'Open any website to inspect its live DOM tree, or use the Console tab below.'
                        : 'Tap Sync or the Pick Element icon above to inspect DOM elements.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  itemCount: _domNodes.length,
                  itemBuilder: (BuildContext context, int index) {
                    final DevToolsDomNode n = _domNodes[index];
                    final bool isSel = sel?.nodeId == n.nodeId;
                    return InkWell(
                      onTap: () => widget.engine.inspectDomNode(n.nodeId),
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          6.0 + (n.depth * 10.0),
                          4,
                          6,
                          4,
                        ),
                        color: isSel
                            ? AppTheme.electricBlue.withValues(alpha: 0.25)
                            : Colors.transparent,
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                            children: <InlineSpan>[
                              TextSpan(
                                text: '<${n.tag}',
                                style: const TextStyle(
                                  color: Color(0xFFF472B6),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (n.idAttr.isNotEmpty)
                                TextSpan(
                                  text: ' id="${n.idAttr}"',
                                  style: const TextStyle(
                                    color: Color(0xFFFBBF24),
                                  ),
                                ),
                              if (n.classAttr.isNotEmpty)
                                TextSpan(
                                  text: ' class="${n.classAttr}"',
                                  style: const TextStyle(
                                    color: Color(0xFF60A5FA),
                                  ),
                                ),
                              const TextSpan(
                                text: '>',
                                style: TextStyle(color: Color(0xFFF472B6)),
                              ),
                              if (n.textPreview.isNotEmpty)
                                TextSpan(
                                  text: ' ${n.textPreview}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConsoleTab() {
    final List<DevToolsConsoleEntry> logs = widget.engine.consoleEntries;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: const Color(0xFF0F172A),
          child: Row(
            children: <Widget>[
              Text(
                '${logs.length} messages',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const Spacer(),
              _MiniActionBtn(
                label: 'Clear',
                onTap: widget.engine.clearConsoleLogs,
              ),
              const SizedBox(width: 6),
              _MiniActionBtn(
                label: 'Copy All',
                onTap: () {
                  final String all = logs
                      .map((DevToolsConsoleEntry e) => e.message)
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: all));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: Text(
                    'Console ready. Type JavaScript below (e.g. document.title or 2 + 2).',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 8, color: Colors.white.withValues(alpha: 0.07)),
                  itemBuilder: (BuildContext context, int index) {
                    final DevToolsConsoleEntry item = logs[index];
                    final Color textColor = item.isError
                        ? const Color(0xFFFCA5A5)
                        : item.isWarning
                        ? const Color(0xFFFDE68A)
                        : item.level == 'input'
                        ? const Color(0xFF93C5FD)
                        : item.level == 'result'
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFE2E8F0);
                    return SelectableText(
                      item.source.isNotEmpty
                          ? '${item.message}  (${item.source}:${item.line})'
                          : item.message,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: textColor,
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 8, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111C33),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Text(
                '> ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF60A5FA),
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: TextField(
                  key: const Key('devtools_console_input'),
                  controller: _consoleInputCtrl,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: Colors.white,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (String code) async {
                    _consoleInputCtrl.clear();
                    await widget.engine.evaluateDevToolsJs(code);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Run JavaScript in page...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('devtools_console_run_button'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF60A5FA),
                ),
                onPressed: () async {
                  final String code = _consoleInputCtrl.text;
                  _consoleInputCtrl.clear();
                  await widget.engine.evaluateDevToolsJs(code);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkTab() {
    final List<DevToolsNetworkEntry> source = _netEntries.isNotEmpty
        ? _netEntries
        : widget.engine.networkEntries;
    final List<DevToolsNetworkEntry> filtered = source.where((
      DevToolsNetworkEntry e,
    ) {
      if (_netFilter == 'all') return true;
      if (_netFilter == 'blocked') return e.blocked;
      if (_netFilter == 'xhr') return e.type == 'fetch' || e.type == 'xhr';
      return e.type.contains(_netFilter);
    }).toList(growable: false);

    return Column(
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: <Widget>[
              for (final (String id, String label) in const <(String, String)>[
                ('all', 'All'),
                ('xhr', 'Fetch/XHR'),
                ('script', 'JS'),
                ('css', 'CSS'),
                ('img', 'Img'),
                ('blocked', 'Blocked Ads/Redirects'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _MiniActionBtn(
                    label: label,
                    active: _netFilter == id,
                    onTap: () => setState(() => _netFilter = id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No network requests captured for this filter yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 6,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final DevToolsNetworkEntry e = filtered[index];
                    final Color statusColor = e.blocked
                        ? const Color(0xFFF87171)
                        : (e.status >= 400
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF34D399));
                    return InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: e.url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied request URL'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 58,
                              child: Text(
                                e.blocked ? 'BLOCKED' : '${e.status} ${e.method}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              e.blocked ? 'Shield' : '${e.durationMs}ms',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStorageTab() {
    final Map<Object?, Object?> localMap =
        (_storageAndInfo['localStorage'] as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};
    final Map<Object?, Object?> sessionMap =
        (_storageAndInfo['sessionStorage'] as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};
    final String cookies = _storageAndInfo['cookies']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(10),
      children: <Widget>[
        const Text(
          'Cookies (document.cookie)',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF93C5FD),
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          cookies.isEmpty ? '(No JS-accessible cookies on this page)' : cookies,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'localStorage (${localMap.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF93C5FD),
          ),
        ),
        const SizedBox(height: 4),
        if (localMap.isEmpty)
          const Text(
            '(Empty)',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          )
        else
          for (final MapEntry<Object?, Object?> e in localMap.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${e.key}: ${e.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 15,
                      color: Colors.white54,
                    ),
                    onPressed: () async {
                      await widget.engine.updateWebStorageItem(
                        session: false,
                        key: e.key.toString(),
                      );
                      await _refreshCurrentTab();
                    },
                  ),
                ],
              ),
            ),
        const SizedBox(height: 10),
        Text(
          'sessionStorage (${sessionMap.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF93C5FD),
          ),
        ),
        const SizedBox(height: 4),
        if (sessionMap.isEmpty)
          const Text(
            '(Empty)',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          )
        else
          for (final MapEntry<Object?, Object?> e in sessionMap.entries)
            Text(
              '${e.key}: ${e.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
      ],
    );
  }

  Widget _buildInfoTab() {
    final String ua = _storageAndInfo['userAgent']?.toString() ?? '';
    final String vp = _storageAndInfo['viewport']?.toString() ?? '';
    final String plat = _storageAndInfo['platform']?.toString() ?? '';
    final int nodes = (_storageAndInfo['domNodes'] as num?)?.toInt() ?? 0;
    final int loadMs = (_storageAndInfo['loadMs'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Live Edit Page Text (document.designMode)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          subtitle: const Text(
            'Tap anywhere on the webpage to type or edit text live',
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
          value: widget.engine.isPageDesignMode,
          onChanged: (bool val) => widget.engine.setPageDesignMode(val),
        ),
        const Divider(color: Colors.white12),
        _InfoRow(label: 'Viewport', value: vp),
        _InfoRow(label: 'DOM Elements', value: '$nodes nodes • Load ${loadMs}ms'),
        _InfoRow(
          label: 'Shield Blocked',
          value: '${widget.engine.pageBlockedCount} ads/redirects blocked on page',
        ),
        _InfoRow(label: 'Platform', value: plat),
        _InfoRow(label: 'User-Agent', value: ua),
      ],
    );
  }
}

class _DevTabChip extends StatelessWidget {
  const _DevTabChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeError = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool badgeError;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.electricBlue.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: active
              ? Border.all(color: AppTheme.electricBlue, width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: badgeError
                ? const Color(0xFFFCA5A5)
                : (active ? Colors.white : Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _MiniActionBtn extends StatelessWidget {
  const _MiniActionBtn({
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.electricBlue
              : Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: danger ? const Color(0xFFFCA5A5) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF93C5FD),
            ),
          ),
          const SizedBox(height: 1),
          SelectableText(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
