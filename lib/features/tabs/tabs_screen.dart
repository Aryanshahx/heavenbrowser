import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../../core/widgets/site_logo.dart';
import '../shield/native_shield_bridge.dart';
import 'tab_manager.dart';

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key, required this.tabManager});

  final TabManagerController tabManager;

  static Future<TabGroup?> showCreateGroupDialog(
    BuildContext context, {
    required TabManagerController tabManager,
    required String tabId,
  }) {
    return showDialog<TabGroup>(
      context: context,
      builder: (BuildContext _) =>
          _CreateTabGroupDialog(tabManager: tabManager, tabId: tabId),
    );
  }

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  late bool _viewingIncognito;
  String? _selectedGroupId;
  bool _authenticatingIncognito = false;
  String? _draggingTabId;
  ScrollController? _gridScrollController;
  String _lastPositionedSignature = '';
  final GlobalKey _gridViewportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _viewingIncognito = widget.tabManager.isActiveIncognito;
  }

  @override
  void dispose() {
    _gridScrollController?.dispose();
    super.dispose();
  }

  double _computeActiveTabScrollOffset({
    required List<BrowserTab> tabs,
    required int columns,
    required double cardHeight,
    required double crossSpacing,
    required double viewportHeight,
    double topPad = 8.0,
    double bottomPad = 18.0,
  }) {
    if (tabs.isEmpty || columns <= 0 || viewportHeight <= 0) {
      return 0.0;
    }
    final String activeId = widget.tabManager.activeTab.id;
    final int activeIndex = tabs.indexWhere(
      (BrowserTab t) => t.id == activeId,
    );
    if (activeIndex <= 0) {
      return 0.0;
    }
    final int totalRows = (tabs.length + columns - 1) ~/ columns;
    final double contentHeight =
        topPad +
        bottomPad +
        (totalRows * cardHeight) +
        (math.max(0, totalRows - 1) * crossSpacing);
    final double maxScrollExtent = math.max(0.0, contentHeight - viewportHeight);
    if (maxScrollExtent <= 0) {
      return 0.0;
    }
    final int activeRow = activeIndex ~/ columns;
    if (activeRow <= 0) {
      return 0.0;
    }
    final double rowTop = topPad + (activeRow * (cardHeight + crossSpacing));
    final double centeredMargin = math.max(
      0.0,
      (viewportHeight - cardHeight) * 0.35,
    );
    return (rowTop - centeredMargin).clamp(0.0, maxScrollExtent);
  }

  void _handleDragAutoScroll(DragUpdateDetails details) {
    final ScrollController? controller = _gridScrollController;
    if (controller == null || !controller.hasClients) return;
    final BuildContext? boxCtx = _gridViewportKey.currentContext;
    if (boxCtx == null) return;
    final RenderBox? renderBox = boxCtx.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final Offset local = renderBox.globalToLocal(details.globalPosition);
    const double edgeZone = 68.0;
    const double maxStep = 14.0;
    final ScrollPosition pos = controller.position;

    if (local.dy < edgeZone && pos.pixels > pos.minScrollExtent) {
      final double factor = ((edgeZone - local.dy) / edgeZone).clamp(0.15, 1.0);
      controller.jumpTo(
        (pos.pixels - (maxStep * factor)).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        ),
      );
    } else if (local.dy > renderBox.size.height - edgeZone &&
        pos.pixels < pos.maxScrollExtent) {
      final double factor =
          ((local.dy - (renderBox.size.height - edgeZone)) / edgeZone).clamp(
            0.15,
            1.0,
          );
      controller.jumpTo(
        (pos.pixels + (maxStep * factor)).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        ),
      );
    }
  }

  Future<void> _unlockIncognitoWithBiometrics() async {
    if (_authenticatingIncognito) return;
    setState(() => _authenticatingIncognito = true);
    final bool ok = await NativeShieldBridge.instance.authenticateBiometric(
      reason: 'Unlock Private Incognito Tabs in Heaven',
    );
    if (!mounted) return;
    setState(() => _authenticatingIncognito = false);
    if (ok) {
      widget.tabManager.markIncognitoUnlocked(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication cancelled or failed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: ListenableBuilder(
        listenable: widget.tabManager,
        builder: (BuildContext context, _) {
          final ThemeData theme = _viewingIncognito
              ? AppTheme.incognitoTheme
              : Theme.of(context);
          final ColorScheme colors = theme.colorScheme;
          final bool isDark = theme.brightness == Brightness.dark;
          final List<BrowserTab> allModeTabs = _viewingIncognito
              ? widget.tabManager.incognitoTabs
              : widget.tabManager.normalTabs;
          final List<BrowserTab> tabs =
              (!_viewingIncognito && _selectedGroupId != null)
              ? allModeTabs
                    .where((BrowserTab t) => t.groupId == _selectedGroupId)
                    .toList(growable: false)
              : allModeTabs;
          final bool incognitoLocked =
              _viewingIncognito && widget.tabManager.isIncognitoLocked;

          return Theme(
            data: theme,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Back to browser',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                titleSpacing: 0,
                title: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildModeToggleBar(colors, isDark),
                    ),
                  ),
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: <Widget>[
                    if (!_viewingIncognito &&
                        widget.tabManager.groups.isNotEmpty)
                      _buildGroupFilterBar(context, colors, isDark),
                    if (_viewingIncognito)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.incognitoCyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.incognitoCyan.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.shield_moon_rounded,
                              size: 18,
                              color: AppTheme.incognitoCyan,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Incognito Mode: History, search queries, and site usage are never saved.',
                                style: TextStyle(fontSize: 12, height: 1.35),
                              ),
                            ),
                            if (widget
                                    .tabManager
                                    .settings
                                    .biometricLockIncognito &&
                                !incognitoLocked)
                              IconButton(
                                tooltip: 'Lock Incognito Tabs',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: AppTheme.incognitoCyan,
                                ),
                                onPressed: () => widget.tabManager
                                    .markIncognitoUnlocked(false),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      key: _gridViewportKey,
                      child: incognitoLocked
                          ? _buildBiometricLockState(colors)
                          : (tabs.isEmpty
                                ? _buildEmptyState(context, colors)
                                : LayoutBuilder(
                                    builder:
                                        (
                                          BuildContext context,
                                          BoxConstraints constraints,
                                        ) {
                                          final double maxW =
                                              constraints.maxWidth;
                                          final int columns;
                                          final double aspectRatio;
                                          final double basePad;
                                          if (maxW >= 1140) {
                                            columns = 5;
                                            aspectRatio = 0.88;
                                            basePad = 22.0;
                                          } else if (maxW >= 840) {
                                            columns = 4;
                                            aspectRatio = 0.84;
                                            basePad = 18.0;
                                          } else if (maxW >= 600) {
                                            columns = 3;
                                            aspectRatio = 0.78;
                                            basePad = 16.0;
                                          } else {
                                            columns = 2;
                                            aspectRatio = 0.58;
                                            basePad = 12.0;
                                          }
                                          final double extraSidePad =
                                              maxW > 1400
                                              ? (maxW - 1400) / 2.0
                                              : 0.0;
                                          final double hPad =
                                              basePad + extraSidePad;
                                          final double crossSpacing =
                                              maxW >= 600 ? 14.0 : 12.0;
                                          final double cardWidth =
                                              (maxW -
                                                  (hPad * 2) -
                                                  (crossSpacing *
                                                      (columns - 1))) /
                                              columns;
                                          final double cardHeight =
                                              cardWidth / aspectRatio;
                                          final double initialOffset =
                                              _computeActiveTabScrollOffset(
                                                tabs: tabs,
                                                columns: columns,
                                                cardHeight: cardHeight,
                                                crossSpacing: crossSpacing,
                                                viewportHeight:
                                                    constraints.maxHeight,
                                              );
                                          final String viewSig =
                                              '$_viewingIncognito|$_selectedGroupId';
                                          if (_gridScrollController == null) {
                                            _gridScrollController =
                                                ScrollController(
                                                  initialScrollOffset:
                                                      initialOffset,
                                                );
                                            _lastPositionedSignature = viewSig;
                                          } else if (_lastPositionedSignature !=
                                              viewSig) {
                                            _lastPositionedSignature = viewSig;
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  final ScrollController? ctrl =
                                                      _gridScrollController;
                                                  if (mounted &&
                                                      ctrl != null &&
                                                      ctrl.hasClients) {
                                                    ctrl.jumpTo(
                                                      initialOffset.clamp(
                                                        ctrl
                                                            .position
                                                            .minScrollExtent,
                                                        ctrl
                                                            .position
                                                            .maxScrollExtent,
                                                      ),
                                                    );
                                                  }
                                                });
                                          }

                                          return GridView.builder(
                                            key: const Key('tabs_grid_view'),
                                            controller: _gridScrollController,
                                            padding: EdgeInsets.fromLTRB(
                                              hPad,
                                              8,
                                              hPad,
                                              18,
                                            ),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: columns,
                                                  mainAxisSpacing:
                                                      crossSpacing,
                                                  crossAxisSpacing:
                                                      crossSpacing,
                                                  childAspectRatio: aspectRatio,
                                                ),
                                            itemCount: tabs.length,
                                            itemBuilder:
                                                (
                                                  BuildContext context,
                                                  int index,
                                                ) {
                                                  return _buildDraggableTabSlot(
                                                    context,
                                                    theme: theme,
                                                    colors: colors,
                                                    isDark: isDark,
                                                    tab: tabs[index],
                                                    cardWidth: cardWidth,
                                                    cardHeight: cardHeight,
                                                  );
                                                },
                                          );
                                        },
                                  )),
                    ),
                    if (!incognitoLocked)
                      _buildBottomBar(context, colors, tabs),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBiometricLockState(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.incognitoCyan.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                size: 38,
                color: AppTheme.incognitoCyan,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Incognito Tabs Locked',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Verify your fingerprint, face, or device PIN to view private Incognito tabs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('unlock_incognito_biometric_button'),
              onPressed: _authenticatingIncognito
                  ? null
                  : _unlockIncognitoWithBiometrics,
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text(
                _authenticatingIncognito ? 'Verifying...' : 'Unlock Incognito',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggleBar(ColorScheme colors, bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ModeTabButton(
              selected: !_viewingIncognito,
              icon: Icons.tab_rounded,
              label: 'Tabs (${widget.tabManager.normalTabs.length})',
              accent: colors.primary,
              onTap: () => setState(() => _viewingIncognito = false),
            ),
          ),
          Expanded(
            child: _ModeTabButton(
              selected: _viewingIncognito,
              icon: Icons.shield_moon_rounded,
              label: 'Incognito (${widget.tabManager.incognitoTabs.length})',
              accent: AppTheme.incognitoCyan,
              onTap: () {
                setState(() => _viewingIncognito = true);
                if (widget.tabManager.isIncognitoLocked) {
                  _unlockIncognitoWithBiometrics();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                _viewingIncognito
                    ? Icons.shield_moon_rounded
                    : Icons.tab_rounded,
                size: 34,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _viewingIncognito
                  ? 'No Incognito tabs open'
                  : 'No standard tabs open',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _viewingIncognito
                  ? 'Tap New Incognito below to browse privately with zero saved trace.'
                  : 'Tap New Tab below to start browsing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableTabSlot(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colors,
    required bool isDark,
    required BrowserTab tab,
    required double cardWidth,
    required double cardHeight,
  }) {
    return RepaintBoundary(
      key: ValueKey<String>('tab_card_${tab.id}'),
      child: DragTarget<String>(
        key: ValueKey<String>('tab_drop_target_${tab.id}'),
        onWillAcceptWithDetails: (DragTargetDetails<String> details) {
          final String incomingId = details.data;
          if (incomingId.isEmpty || incomingId == tab.id) {
            return false;
          }
          if (widget.tabManager.moveTab(incomingId, tab.id)) {
            HapticFeedback.selectionClick();
          }
          return true;
        },
        onAcceptWithDetails: (_) {},
        builder:
            (
              BuildContext context,
              List<String?> candidateData,
              List<dynamic> rejectedData,
            ) {
              final Widget cardVisual = _buildFullTabWindowCard(
                context,
                colors: colors,
                isDark: isDark,
                tab: tab,
                isHighlightedTarget: candidateData.isNotEmpty,
              );

              return LongPressDraggable<String>(
                key: ValueKey<String>('tab_draggable_${tab.id}'),
                data: tab.id,
                delay: const Duration(milliseconds: 210),
                onDragStarted: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _draggingTabId = tab.id);
                },
                onDragUpdate: _handleDragAutoScroll,
                onDragEnd: (_) {
                  if (mounted && _draggingTabId != null) {
                    setState(() => _draggingTabId = null);
                  }
                },
                onDraggableCanceled: (_, _) {
                  if (mounted && _draggingTabId != null) {
                    setState(() => _draggingTabId = null);
                  }
                },
                feedback: Theme(
                  data: theme,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 10,
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: Transform.scale(
                        scale: 1.03,
                        child: _buildFullTabWindowCard(
                          context,
                          colors: colors,
                          isDark: isDark,
                          tab: tab,
                          isDragFeedback: true,
                        ),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.28,
                  child: cardVisual,
                ),
                child: cardVisual,
              );
            },
      ),
    );
  }

  Widget _buildFullTabWindowCard(
    BuildContext context, {
    required ColorScheme colors,
    required bool isDark,
    required BrowserTab tab,
    bool isHighlightedTarget = false,
    bool isDragFeedback = false,
  }) {
    final bool isActive = widget.tabManager.activeTab.id == tab.id;
    final bool isPlayingAudio = tab.engine.isMediaPlaying;
    final Color cardBg = tab.isIncognito
        ? const Color(0xFF0D1B22)
        : (isDark ? AppTheme.navySurface : Colors.white);
    final Color headerBg = tab.isIncognito
        ? const Color(0xFF132630)
        : (isDark
              ? AppTheme.navyElevated
              : colors.surfaceContainerHighest.withValues(alpha: 0.72));

    final Color borderColor = isHighlightedTarget
        ? AppTheme.shieldEmerald
        : (isActive
              ? colors.primary
              : (widget.tabManager.groupById(tab.groupId)?.color ??
                    colors.outlineVariant.withValues(alpha: 0.45)));
    final double borderWidth = (isActive || isHighlightedTarget)
        ? 2.6
        : (tab.groupId != null ? 1.8 : 1.1);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        // Paint rounded border in foregroundDecoration ON TOP OF clipped child
        // so all 4 rounded corners of the blue active border stay 100% uncut!
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: isDragFeedback
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.tabManager.switchToTab(tab.id);
                    Navigator.pop(context);
                  },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  height: 36,
                  padding: const EdgeInsets.only(left: 7, right: 1),
                  color: headerBg,
                  child: Row(
                    children: <Widget>[
                      SiteLogo(
                        urlOrDomain: tab.engine.currentUrl,
                        fallbackLabel: tab.displayTitle,
                        size: 17,
                        borderRadius: 5,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          tab.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isPlayingAudio)
                        const Padding(
                          padding: EdgeInsets.only(right: 1),
                          child: Icon(
                            Icons.volume_up_rounded,
                            size: 13,
                            color: AppTheme.shieldEmerald,
                          ),
                        ),
                      if (!tab.isIncognito && !isDragFeedback)
                        IconButton(
                          key: ValueKey<String>('tab_more_button_${tab.id}'),
                          icon: const Icon(Icons.more_vert_rounded, size: 15.5),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 28,
                          ),
                          tooltip: 'Tab options',
                          onPressed: () => _showGroupSheetForTab(context, tab),
                        ),
                      if (!isDragFeedback)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 15.5),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 28,
                          ),
                          tooltip: 'Close tab',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            unawaited(widget.tabManager.closeTab(tab.id));
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (tab.previewBytes != null &&
                          tab.previewBytes!.isNotEmpty)
                        Image.memory(
                          tab.previewBytes!,
                          cacheWidth: 320,
                          filterQuality: FilterQuality.low,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          gaplessPlayback: true,
                        )
                      else
                        _buildSimulatedFullPageFrame(colors, isDark, tab),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  tab.displaySubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimulatedFullPageFrame(
    ColorScheme colors,
    bool isDark,
    BrowserTab tab,
  ) {
    final String urlDisplay = tab.engine.isShowingStartPage
        ? 'Search or type web address'
        : OmniboxParser.formatDisplayUrl(tab.engine.currentUrl);

    return Container(
      color: tab.isIncognito
          ? const Color(0xFF061015)
          : (isDark ? AppTheme.deepNavyBg : const Color(0xFFF3F7FD)),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              urlDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8.5, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          if (tab.engine.isShowingStartPage) ...<Widget>[
            Center(
              child: Text(
                tab.isIncognito ? 'Heaven Incognito' : 'Heaven',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      height: 6,
                      width: 65,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.onSurface.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                SiteLogo(
                  urlOrDomain: tab.engine.currentUrl,
                  fallbackLabel: tab.displayTitle,
                  size: 26,
                  borderRadius: 7,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    tab.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 54,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            for (final double factor in <double>[1.0, 0.88, 0.94, 0.65])
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: FractionallySizedBox(
                  widthFactor: factor,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ColorScheme colors,
    List<BrowserTab> tabs,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: tabs.isNotEmpty
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        children: <Widget>[
          if (tabs.isNotEmpty)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('tabs_bottom_close_all_button'),
                  onPressed: () async {
                    await widget.tabManager.closeAllTabsByMode(
                      incognito: _viewingIncognito,
                    );
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                  label: const Text('Close All'),
                ),
              ),
            ),
          if (tabs.isNotEmpty) const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (!_viewingIncognito) ...<Widget>[
                    FilledButton.tonalIcon(
                      key: const Key('tabs_bottom_new_group_button'),
                      onPressed: () async {
                        String targetTabId;
                        if (widget.tabManager.normalTabs.isEmpty) {
                          final BrowserTab created = await widget.tabManager
                              .openNewTab(incognito: false);
                          targetTabId = created.id;
                        } else if (!widget.tabManager.activeTab.isIncognito) {
                          targetTabId = widget.tabManager.activeTab.id;
                        } else {
                          targetTabId = widget.tabManager.normalTabs.first.id;
                        }
                        if (!context.mounted) return;
                        await TabsScreen.showCreateGroupDialog(
                          context,
                          tabManager: widget.tabManager,
                          tabId: targetTabId,
                        );
                      },
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('New Group'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    key: const Key('tabs_bottom_new_tab_button'),
                    onPressed: () async {
                      await widget.tabManager.openNewTab(
                        incognito: _viewingIncognito,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    icon: Icon(
                      _viewingIncognito
                          ? Icons.shield_moon_rounded
                          : Icons.add_rounded,
                      size: 19,
                    ),
                    label: Text(
                      _viewingIncognito ? 'New Incognito' : 'New Tab',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupFilterBar(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    final List<TabGroup> groups = widget.tabManager.groups;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final TabGroup grp in groups) ...<Widget>[
              InputChip(
                key: ValueKey<String>('tab_group_filter_${grp.id}'),
                showCheckmark: false,
                avatar: CircleAvatar(
                  backgroundColor: grp.color,
                  radius: 5,
                ),
                label: Text(
                  '${grp.name} (${widget.tabManager.normalTabs.where((BrowserTab t) => t.groupId == grp.id).length})',
                ),
                selected: _selectedGroupId == grp.id,
                onSelected: (_) => setState(() {
                  _selectedGroupId = _selectedGroupId == grp.id
                      ? null
                      : grp.id;
                }),
                onDeleted: () {
                  if (_selectedGroupId == grp.id) {
                    setState(() => _selectedGroupId = null);
                  }
                  widget.tabManager.deleteGroup(grp.id);
                },
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupSheetForTab(
    BuildContext context,
    BrowserTab tab,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (BuildContext sheetContext) {
        final double maxSheetH = MediaQuery.sizeOf(sheetContext).height * 0.80;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Tab Options • ${tab.displayTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('add_tab_to_new_group_button'),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await TabsScreen.showCreateGroupDialog(
                        context,
                        tabManager: widget.tabManager,
                        tabId: tab.id,
                      );
                    },
                    icon: const Icon(Icons.workspaces_outline, size: 18),
                    label: const Text('Add tab to new group'),
                  ),
                  if (widget.tabManager.groups.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      'Move to existing group',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      child: Column(
                        children: <Widget>[
                          for (final TabGroup grp in widget.tabManager.groups)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: grp.color,
                                radius: 8,
                              ),
                              title: Text(grp.name),
                              trailing: tab.groupId == grp.id
                                  ? const Icon(Icons.check_circle_rounded)
                                  : null,
                              onTap: () {
                                widget.tabManager.assignTabToGroup(
                                  tab.id,
                                  grp.id,
                                );
                                Navigator.pop(sheetContext);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (tab.groupId != null)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: const Icon(Icons.remove_circle_outline_rounded),
                        title: const Text('Remove from group'),
                        onTap: () {
                          widget.tabManager.assignTabToGroup(tab.id, null);
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: accent.withValues(alpha: 0.55))
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected
                    ? accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateTabGroupDialog extends StatefulWidget {
  const _CreateTabGroupDialog({
    required this.tabManager,
    required this.tabId,
  });

  final TabManagerController tabManager;
  final String tabId;

  @override
  State<_CreateTabGroupDialog> createState() => _CreateTabGroupDialogState();
}

class _CreateTabGroupDialogState extends State<_CreateTabGroupDialog> {
  late final TextEditingController _nameCtrl;
  int _selectedColor = TabGroup.palette.first;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Research');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Add Tab to New Group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Group Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Group Color',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              for (final int c in TabGroup.palette)
                GestureDetector(
                  onTap: () => setState(() => _selectedColor = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: _selectedColor == c
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                    ),
                    child: _selectedColor == c
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm_create_tab_group_button'),
          onPressed: () {
            final TabGroup g = widget.tabManager.createGroupAndAddTab(
              name: _nameCtrl.text,
              tabId: widget.tabId,
              colorValue: _selectedColor,
            );
            Navigator.pop(context, g);
          },
          child: const Text('Create Group'),
        ),
      ],
    );
  }
}
