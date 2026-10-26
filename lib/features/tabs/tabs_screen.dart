import 'dart:async';

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
  }) async {
    final TextEditingController nameCtrl = TextEditingController(
      text: 'Research',
    );
    int selectedColor = TabGroup.palette.first;
    final TabGroup? created = await showDialog<TabGroup>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return AlertDialog(
              title: const Text('Add Tab to New Group'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameCtrl,
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
                    children: <Widget>[
                      for (final int c in TabGroup.palette)
                        GestureDetector(
                          onTap: () => setModalState(() => selectedColor = c),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: selectedColor == c
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : null,
                            ),
                            child: selectedColor == c
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final TabGroup g = tabManager.createGroupAndAddTab(
                      name: nameCtrl.text,
                      tabId: tabId,
                      colorValue: selectedColor,
                    );
                    Navigator.pop(dialogContext, g);
                  },
                  child: const Text('Create Group'),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    return created;
  }

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  late bool _viewingIncognito;
  String? _selectedGroupId;
  bool _authenticatingIncognito = false;
  final Set<String> _closingTabIds = <String>{};

  @override
  void initState() {
    super.initState();
    _viewingIncognito = widget.tabManager.isActiveIncognito;
  }

  Future<void> _animateAndCloseTab(String tabId) async {
    if (_closingTabIds.contains(tabId)) return;
    HapticFeedback.selectionClick();
    setState(() => _closingTabIds.add(tabId));
    await Future<void>.delayed(const Duration(milliseconds: 170));
    if (mounted) {
      _closingTabIds.remove(tabId);
    }
    await widget.tabManager.closeTab(tabId);
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
    return ListenableBuilder(
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
                padding: const EdgeInsets.only(right: 8),
                child: _buildModeToggleBar(colors, isDark),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  if (!_viewingIncognito)
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
                          color: AppTheme.incognitoCyan.withValues(alpha: 0.35),
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
                          if (widget.tabManager.settings.biometricLockIncognito &&
                              !incognitoLocked)
                            IconButton(
                              tooltip: 'Lock Incognito Tabs',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                                color: AppTheme.incognitoCyan,
                              ),
                              onPressed: () =>
                                  widget.tabManager.markIncognitoUnlocked(false),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: incognitoLocked
                          ? KeyedSubtree(
                              key: const ValueKey<String>('tabs_locked'),
                              child: _buildBiometricLockState(colors),
                            )
                          : (tabs.isEmpty
                                ? KeyedSubtree(
                                    key: ValueKey<String>(
                                      'tabs_empty_$_viewingIncognito',
                                    ),
                                    child: _buildEmptyState(context, colors),
                                  )
                                : KeyedSubtree(
                                    key: ValueKey<String>(
                                      'tabs_grid_${_viewingIncognito}_${_selectedGroupId ?? 'all'}',
                                    ),
                                    child: LayoutBuilder(
                                      builder:
                                          (
                                            BuildContext context,
                                            BoxConstraints constraints,
                                          ) {
                                            final int columns =
                                                constraints.maxWidth >= 620
                                                ? 3
                                                : 2;
                                            return GridView.builder(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    12,
                                                    8,
                                                    12,
                                                    18,
                                                  ),
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: columns,
                                                    mainAxisSpacing: 12,
                                                    crossAxisSpacing: 12,
                                                    childAspectRatio: 0.58,
                                                  ),
                                              itemCount: tabs.length,
                                              itemBuilder:
                                                  (
                                                    BuildContext context,
                                                    int index,
                                                  ) {
                                                    return _buildFullTabWindowCard(
                                                      context,
                                                      colors,
                                                      isDark,
                                                      tabs[index],
                                                      index,
                                                    );
                                                  },
                                            );
                                          },
                                    ),
                                  )),
                    ),
                  ),
                  if (!incognitoLocked) _buildBottomBar(context, colors, tabs),
                ],
              ),
            ),
          ),
        );
      },
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

  Widget _buildFullTabWindowCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    BrowserTab tab,
    int index,
  ) {
    final bool isActive = widget.tabManager.activeTab.id == tab.id;
    final bool isClosing = _closingTabIds.contains(tab.id);
    final bool isPlayingAudio = tab.engine.isMediaPlaying;
    final Color cardBg = tab.isIncognito
        ? const Color(0xFF0D1B22)
        : (isDark ? AppTheme.navySurface : Colors.white);
    final Color headerBg = tab.isIncognito
        ? const Color(0xFF132630)
        : (isDark
              ? AppTheme.navyElevated
              : colors.surfaceContainerHighest.withValues(alpha: 0.72));

    final Color borderColor = isActive
        ? colors.primary
        : (widget.tabManager.groupById(tab.groupId)?.color ??
              colors.outlineVariant.withValues(alpha: 0.45));
    final double borderWidth = isActive
        ? 2.6
        : (tab.groupId != null ? 1.8 : 1.1);

    return RepaintBoundary(
      key: ValueKey<String>('tab_card_${tab.id}'),
      child: Dismissible(
        key: ValueKey<String>('tab_dismiss_${tab.id}'),
        direction: DismissDirection.horizontal,
        movementDuration: const Duration(milliseconds: 180),
        resizeDuration: const Duration(milliseconds: 140),
        onDismissed: (_) {
          HapticFeedback.lightImpact();
          unawaited(widget.tabManager.closeTab(tab.id));
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.92, end: 1.0),
          duration: Duration(milliseconds: 180 + ((index % 6) * 22)),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double entranceScale, Widget? child) {
            return Transform.scale(scale: entranceScale, child: child);
          },
          child: AnimatedOpacity(
            opacity: isClosing ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 155),
            curve: Curves.easeInOut,
            child: AnimatedScale(
              scale: isClosing ? 0.76 : (isActive ? 1.0 : 0.988),
              duration: const Duration(milliseconds: 170),
              curve: isClosing ? Curves.easeInCubic : Curves.easeOutCubic,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isActive
                        ? <BoxShadow>[
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.28),
                              blurRadius: 10,
                              spreadRadius: 0.5,
                            ),
                          ]
                        : <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.24 : 0.08,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.tabManager.switchToTab(tab.id);
                        Navigator.pop(context);
                      },
                      onLongPress: tab.isIncognito
                          ? null
                          : () => _showGroupSheetForTab(context, tab),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Container(
                            height: 36,
                            padding: const EdgeInsets.only(left: 8, right: 2),
                            color: headerBg,
                            child: Row(
                              children: <Widget>[
                                if (widget.tabManager.groupById(tab.groupId)
                                    case final TabGroup grp) ...<Widget>[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: grp.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                SiteLogo(
                                  urlOrDomain: tab.engine.currentUrl,
                                  fallbackLabel: tab.displayTitle,
                                  size: 18,
                                  borderRadius: 5,
                                ),
                                const SizedBox(width: 6),
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
                                  Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: Icon(
                                      Icons.volume_up_rounded,
                                      size: 14,
                                      color: AppTheme.shieldEmerald,
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  tooltip: 'Close tab',
                                  onPressed: () => _animateAndCloseTab(tab.id),
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
                                  _buildSimulatedFullPageFrame(
                                    colors,
                                    isDark,
                                    tab,
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      18,
                                      8,
                                      6,
                                    ),
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
                                              borderRadius:
                                                  BorderRadius.circular(5),
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
              ),
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
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ColorScheme colors,
    List<BrowserTab> tabs,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
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
                label: Text(_viewingIncognito ? 'New Incognito' : 'New Tab'),
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
            ChoiceChip(
              label: Text('All (${widget.tabManager.normalTabs.length})'),
              selected: _selectedGroupId == null,
              onSelected: (_) => setState(() => _selectedGroupId = null),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            for (final TabGroup grp in groups) ...<Widget>[
              InputChip(
                showCheckmark: false,
                avatar: CircleAvatar(
                  backgroundColor: grp.color,
                  radius: 5,
                ),
                label: Text(
                  '${grp.name} (${widget.tabManager.normalTabs.where((BrowserTab t) => t.groupId == grp.id).length})',
                ),
                selected: _selectedGroupId == grp.id,
                onSelected: (_) => setState(() => _selectedGroupId = grp.id),
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
            ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('New Group'),
              visualDensity: VisualDensity.compact,
              onPressed: () => TabsScreen.showCreateGroupDialog(
                context,
                tabManager: widget.tabManager,
                tabId: widget.tabManager.activeTab.id,
              ),
            ),
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
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Tab Group • ${tab.displayTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (final TabGroup grp in widget.tabManager.groups)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: grp.color,
                      radius: 8,
                    ),
                    title: Text(grp.name),
                    trailing: tab.groupId == grp.id
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                    onTap: () {
                      widget.tabManager.assignTabToGroup(tab.id, grp.id);
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (tab.groupId != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.remove_circle_outline_rounded),
                    title: const Text('Remove from group'),
                    onTap: () {
                      widget.tabManager.assignTabToGroup(tab.id, null);
                      Navigator.pop(sheetContext);
                    },
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await TabsScreen.showCreateGroupDialog(
                      context,
                      tabManager: widget.tabManager,
                      tabId: tab.id,
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add tab to new group'),
                ),
              ],
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
