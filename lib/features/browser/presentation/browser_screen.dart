import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../../core/widgets/search_engine_chip_button.dart';
import '../../../core/widgets/site_logo.dart';
import '../../devtools/desktop_inspector_panel.dart';
import '../../downloads/downloads_controller.dart';
import '../../downloads/downloads_screen.dart';
import '../../news/interest_news_service.dart';
import '../../search/heaven_search_service.dart';
import '../../settings/browser_settings.dart';
import '../../settings/help_screen.dart';
import '../../settings/languages_screen.dart';
import '../../settings/notifications_screen.dart';
import '../../settings/settings_screen.dart';
import '../../shield/native_shield_bridge.dart';
import '../../tabs/tab_manager.dart';
import '../../tabs/tabs_screen.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_screen.dart';
import '../engine/browser_engine.dart';
import '../site_controls_sheet.dart';
import 'widgets/library_screen.dart';
import 'widgets/reader_mode_sheet.dart';
import 'widgets/start_page.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.settings,
    required this.tabManager,
    required this.searchService,
    required this.downloads,
    required this.newsService,
    required this.interests,
    required this.vpn,
  });

  final BrowserSettingsController settings;
  final TabManagerController tabManager;
  final HeavenSearchService searchService;
  final DownloadsController downloads;
  final HeavenNewsFeedService newsService;
  final InterestProfileController interests;
  final VpnController vpn;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  final TextEditingController _omniboxController = TextEditingController();
  final FocusNode _omniboxFocusNode = FocusNode();
  final TextEditingController _findController = TextEditingController();

  Timer? _suggestDebounce;
  Timer? _downloadPopupTimer;
  List<String> _liveSuggestions = <String>[];
  String? _downloadPopupMessage;
  bool _isEditingOmnibox = false;
  bool _showLinkActionsCard = false;
  bool _showFindBar = false;
  bool _showInspectorPanel = false;
  int _findMatches = 0;

  // Edge-swipe Back / Forward & Top-bar Tab-Swipe state
  double _leftEdgeDragPx = 0.0;
  double _rightEdgeDragPx = 0.0;
  double _topBarSwipeDx = 0.0;

  BrowserEngine get _activeEngine => widget.tabManager.activeEngine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.downloads.onDownloadToast = _showDownloadStartedPopup;
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _downloadPopupTimer?.cancel();
    if (widget.downloads.onDownloadToast == _showDownloadStartedPopup) {
      widget.downloads.onDownloadToast = null;
    }
    for (final BrowserTab tab in widget.tabManager.allTabs) {
      tab.engine.onSitePermissionPrompt = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _omniboxController.dispose();
    _omniboxFocusNode.dispose();
    _findController.dispose();
    super.dispose();
  }

  void _showDownloadStartedPopup(String message) {
    if (!mounted) return;
    _downloadPopupTimer?.cancel();
    setState(() {
      _downloadPopupMessage = message;
    });
    _downloadPopupTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _downloadPopupMessage == message) {
        setState(() => _downloadPopupMessage = null);
      }
    });
  }

  void _dismissDownloadPopup() {
    _downloadPopupTimer?.cancel();
    if (_downloadPopupMessage != null) {
      setState(() => _downloadPopupMessage = null);
    }
  }

  Future<void> _openDownloadsTab() async {
    _dismissDownloadPopup();
    _closeOmniboxOverlay();
    await widget.tabManager.openDownloadsTab();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (widget.settings.clearOnExit) {
        unawaited(widget.tabManager.burnAllSessionsAndData());
      } else {
        unawaited(
          widget.tabManager.captureTabPreview(widget.tabManager.activeTab),
        );
      }
    }
  }

  Future<bool> _promptSitePermission(
    String host,
    List<SitePermissionType> types,
  ) async {
    if (!mounted) return false;
    final String joined = types
        .map((SitePermissionType t) => t.label)
        .join(', ');
    final bool? granted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.security_rounded, size: 32),
          title: Text('$host wants permission'),
          content: Text(
            'Allow $host to access $joined?\n\nYou can revoke this anytime with 1 tap from the Site Permission Dashboard.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Block'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    return granted == true;
  }

  String _editableLinkForEngine(BrowserEngine engine) {
    final String? url = engine.currentUrl;
    if (OmniboxParser.isDownloadsUrl(url)) {
      return AppConstants.downloadsTabUrl;
    }
    final String searchQ = OmniboxParser.extractAnySearchQuery(url);
    if (searchQ.isNotEmpty) {
      return searchQ;
    }
    return url ?? '';
  }

  String _shareableLinkForEngine(BrowserEngine engine) {
    return engine.currentUrl ?? '';
  }

  void _beginOmniboxEdit() {
    final bool hasActiveLink = _activeEngine.isShowingWebPage;
    _omniboxController.clear();
    setState(() {
      _isEditingOmnibox = true;
      _showLinkActionsCard = hasActiveLink;
      _liveSuggestions = <String>[];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _omniboxFocusNode.requestFocus();
      }
    });
  }

  void _populateCurrentUrlForEditing() {
    final String editable = _editableLinkForEngine(_activeEngine);
    _omniboxController.text = editable;
    _omniboxController.selection = TextSelection.collapsed(
      offset: editable.length,
    );
    setState(() {
      _isEditingOmnibox = true;
      _showLinkActionsCard = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _omniboxFocusNode.requestFocus();
      }
    });
  }

  void _closeOmniboxOverlay() {
    _suggestDebounce?.cancel();
    _omniboxFocusNode.unfocus();
    if (_isEditingOmnibox ||
        _showLinkActionsCard ||
        _liveSuggestions.isNotEmpty) {
      setState(() {
        _isEditingOmnibox = false;
        _showLinkActionsCard = false;
        _liveSuggestions = <String>[];
      });
    }
  }

  void _onOmniboxTextChanged(String text) {
    setState(() {
      if (text.isNotEmpty && _showLinkActionsCard) {
        _showLinkActionsCard = false;
      }
    });
    _suggestDebounce?.cancel();
    final String trimmed = text.trim();
    if (trimmed.length < 2) {
      if (_liveSuggestions.isNotEmpty) {
        setState(() => _liveSuggestions = <String>[]);
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 90), () async {
      final List<String> fetched = await widget.searchService.fetchSuggestions(
        trimmed,
      );
      if (mounted && _isEditingOmnibox) {
        setState(() => _liveSuggestions = fetched);
      }
    });
  }

  Future<void> _submitOmnibox([String? overrideValue]) async {
    final String raw = (overrideValue ?? _omniboxController.text).trim();
    _closeOmniboxOverlay();
    if (raw.isEmpty) {
      return;
    }
    if (!widget.tabManager.isActiveIncognito &&
        !OmniboxParser.isDownloadsUrl(raw)) {
      unawaited(widget.interests.recordActivity(text: raw, weight: 2.2));
    }
    await _activeEngine.loadUserEntry(raw);
  }

  Future<void> _triggerVoiceSearch() async {
    final String? spoken = await NativeShieldBridge.instance.startVoiceSearch();
    if (!mounted || spoken == null) {
      return;
    }
    if (spoken == '__UNAVAILABLE__') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice recognition service is not installed on this device',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final String clean = spoken.trim();
    if (clean.isEmpty) {
      return;
    }
    await _submitOmnibox(clean);
  }

  void _handleTopBarHorizontalEnd(DragEndDetails details) {
    final double vx = details.primaryVelocity ?? 0.0;
    final double dx = _topBarSwipeDx;
    _topBarSwipeDx = 0.0;
    if (dx <= -42 || vx <= -260) {
      if (widget.tabManager.switchAdjacentTab(1)) {
        HapticFeedback.selectionClick();
      }
    } else if (dx >= 42 || vx >= 260) {
      if (widget.tabManager.switchAdjacentTab(-1)) {
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.tabManager,
        widget.settings,
      ]),
      builder: (BuildContext context, _) {
        final bool incognito = widget.tabManager.isActiveIncognito;
        final ThemeData effectiveTheme = incognito
            ? AppTheme.incognitoTheme
            : Theme.of(context);
        final ColorScheme colors = effectiveTheme.colorScheme;
        final BrowserEngine engine = _activeEngine;

        engine.onSitePermissionPrompt ??= _promptSitePermission;

        final bool showLinkActions =
            _isEditingOmnibox && _showLinkActionsCard && engine.isShowingWebPage;
        final List<String> recentMatches = (_isEditingOmnibox && !incognito)
            ? widget.settings.matchingRecentSearches(
                _omniboxController.text,
                limit: 6,
              )
            : const <String>[];
        final bool showOverlayPanel =
            showLinkActions ||
            (_isEditingOmnibox &&
                (_liveSuggestions.isNotEmpty || recentMatches.isNotEmpty));

        return Theme(
          data: effectiveTheme,
          child: ListenableBuilder(
            listenable: engine,
            builder: (BuildContext context, _) {
              final bool showTopNavBar =
                  _isEditingOmnibox ||
                  !engine.isShowingWebPage ||
                  engine.isNavBarVisible;

              return PopScope<void>(
                canPop:
                    !engine.canGoBack &&
                    !_isEditingOmnibox &&
                    !_showLinkActionsCard &&
                    !_showFindBar &&
                    !_showInspectorPanel,
                onPopInvokedWithResult: (bool didPop, void _) async {
                  if (didPop) {
                    return;
                  }
                  if (_isEditingOmnibox || _showLinkActionsCard) {
                    _closeOmniboxOverlay();
                    return;
                  }
                  if (_showFindBar) {
                    setState(() => _showFindBar = false);
                    return;
                  }
                  if (_showInspectorPanel) {
                    setState(() => _showInspectorPanel = false);
                    unawaited(engine.clearInspectorHighlight());
                    return;
                  }
                  if (engine.canGoBack) {
                    await engine.goBack();
                  }
                },
                child: Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          key: const Key('top_navigation_bar_wrapper'),
                          width: double.infinity,
                          child: showTopNavBar
                              ? _buildCommandCapsuleBar(context, colors, engine)
                              : const SizedBox.shrink(),
                        ),
                        if (_showFindBar) _buildFindBar(colors),
                        Expanded(
                          child: Stack(
                            children: <Widget>[
                              RepaintBoundary(
                                child: ValueListenableBuilder<int>(
                                  valueListenable:
                                      widget.tabManager.viewportRevision,
                                  builder: (BuildContext context, int _, _) {
                                    return _buildTabsViewport(colors);
                                  },
                                ),
                              ),
                              if (engine.isLoading)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: RepaintBoundary(
                                    child: IgnorePointer(
                                      child: LinearProgressIndicator(
                                        value:
                                            engine.progress > 0 &&
                                                engine.progress < 1
                                            ? engine.progress
                                            : null,
                                        minHeight: 2.5,
                                        backgroundColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                              if (engine.pullProgress > 0.02)
                                Positioned(
                                  top: 10 + (engine.pullProgress * 46),
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: _buildPullRefreshBadge(
                                      colors,
                                      engine.pullProgress,
                                    ),
                                  ),
                                ),
                              if (!_isEditingOmnibox &&
                                  !(incognito &&
                                      widget.tabManager.isIncognitoLocked))
                                ..._buildEdgeSwipeGestureZones(colors, engine),
                              if (_downloadPopupMessage != null)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 14,
                                  child: _buildDownloadStartedPopupCard(colors),
                                ),
                              if (incognito &&
                                  widget.tabManager.isIncognitoLocked)
                                Positioned.fill(
                                  child: _buildIncognitoLockOverlay(colors),
                                ),
                              if (_isEditingOmnibox || _showLinkActionsCard)
                                Positioned.fill(
                                  child: GestureDetector(
                                    key: const Key(
                                      'omnibox_outside_dismiss_scrim',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _closeOmniboxOverlay,
                                    child: Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                ),
                              if (showOverlayPanel)
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  top: 8,
                                  child: _buildOmniboxOverlayPanel(
                                    context,
                                    colors,
                                    engine,
                                    showLinkActions: showLinkActions,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_showInspectorPanel)
                          DesktopInspectorPanel(
                            engine: engine,
                            onClose: () {
                              setState(() => _showInspectorPanel = false);
                              unawaited(engine.clearInspectorHighlight());
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _buildEdgeSwipeGestureZones(
    ColorScheme colors,
    BrowserEngine engine,
  ) {
    final double leftProgress = (_leftEdgeDragPx / 64.0).clamp(0.0, 1.0);
    final double rightProgress = (_rightEdgeDragPx / 64.0).clamp(0.0, 1.0);

    return <Widget>[
      if (engine.canGoBack)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: GestureDetector(
            key: const Key('left_edge_back_gesture_zone'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              setState(() => _leftEdgeDragPx = 2.0);
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) {
              setState(() {
                _leftEdgeDragPx = (_leftEdgeDragPx + d.delta.dx).clamp(
                  0.0,
                  110.0,
                );
              });
            },
            onHorizontalDragCancel: () {
              if (_leftEdgeDragPx != 0) {
                setState(() => _leftEdgeDragPx = 0.0);
              }
            },
            onHorizontalDragEnd: (DragEndDetails d) {
              final double vx = d.primaryVelocity ?? 0.0;
              final bool trigger = _leftEdgeDragPx >= 56.0 || vx > 360.0;
              setState(() => _leftEdgeDragPx = 0.0);
              if (trigger && engine.canGoBack) {
                HapticFeedback.lightImpact();
                unawaited(engine.goBack());
              }
            },
          ),
        ),
      if (engine.canGoForward)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: GestureDetector(
            key: const Key('right_edge_forward_gesture_zone'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              setState(() => _rightEdgeDragPx = 2.0);
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) {
              setState(() {
                _rightEdgeDragPx = (_rightEdgeDragPx - d.delta.dx).clamp(
                  0.0,
                  110.0,
                );
              });
            },
            onHorizontalDragCancel: () {
              if (_rightEdgeDragPx != 0) {
                setState(() => _rightEdgeDragPx = 0.0);
              }
            },
            onHorizontalDragEnd: (DragEndDetails d) {
              final double vx = d.primaryVelocity ?? 0.0;
              final bool trigger = _rightEdgeDragPx >= 56.0 || vx < -360.0;
              setState(() => _rightEdgeDragPx = 0.0);
              if (trigger && engine.canGoForward) {
                HapticFeedback.lightImpact();
                unawaited(engine.goForward());
              }
            },
          ),
        ),
      if (leftProgress > 0.04)
        Positioned(
          left: -28 + (leftProgress * 44),
          top: 0,
          bottom: 0,
          child: Center(
            child: IgnorePointer(
              child: Material(
                elevation: 6,
                shape: const CircleBorder(),
                color: leftProgress >= 0.88
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 17,
                    color: leftProgress >= 0.88
                        ? colors.onPrimary
                        : colors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      if (rightProgress > 0.04)
        Positioned(
          right: -28 + (rightProgress * 44),
          top: 0,
          bottom: 0,
          child: Center(
            child: IgnorePointer(
              child: Material(
                elevation: 6,
                shape: const CircleBorder(),
                color: rightProgress >= 0.88
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 17,
                    color: rightProgress >= 0.88
                        ? colors.onPrimary
                        : colors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildDownloadStartedPopupCard(ColorScheme colors) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('download_started_popup_banner'),
        borderRadius: BorderRadius.circular(16),
        onTap: _openDownloadsTab,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.shieldEmerald.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.downloading_rounded,
                  size: 18,
                  color: AppTheme.shieldEmerald,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _downloadPopupMessage ?? 'Download started',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Tap to view in Downloads tab',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _dismissDownloadPopup,
                icon: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncognitoLockOverlay(ColorScheme colors) {
    return Material(
      color: const Color(0xFF061015),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.fingerprint_rounded,
                size: 46,
                color: AppTheme.incognitoCyan,
              ),
              const SizedBox(height: 14),
              const Text(
                'Private Incognito Session Locked',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Verify your fingerprint or face unlock to access Incognito tabs.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: <Widget>[
                  if (widget.tabManager.normalTabs.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => widget.tabManager.switchToTab(
                        widget.tabManager.normalTabs.last.id,
                      ),
                      child: const Text('Switch to Normal Tab'),
                    ),
                  FilledButton.icon(
                    key: const Key('unlock_active_incognito_button'),
                    onPressed: () async {
                      final bool ok = await NativeShieldBridge.instance
                          .authenticateBiometric(
                            reason: 'Unlock Private Incognito Tab',
                          );
                      if (ok) {
                        widget.tabManager.markIncognitoUnlocked(true);
                      }
                    },
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPullRefreshBadge(ColorScheme colors, double pullProgress) {
    final bool armed = pullProgress >= 0.96;
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: armed ? colors.primary : colors.surfaceContainerHighest,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Transform.rotate(
          angle: pullProgress * math.pi * 1.8,
          child: Icon(
            Icons.refresh_rounded,
            size: 22,
            color: armed ? colors.onPrimary : colors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildTabsViewport(ColorScheme colors) {
    final List<BrowserTab> tabs = widget.tabManager.allTabs;
    final int activeIndex = widget.tabManager.activeTabIndex;

    return IndexedStack(
      index: activeIndex,
      children: <Widget>[
        for (int i = 0; i < tabs.length; i++)
          KeyedSubtree(
            key: ValueKey<String>(tabs[i].id),
            child: TickerMode(
              enabled: i == activeIndex,
              child: RepaintBoundary(
                key: tabs[i].repaintKey,
                child: _buildSingleTabBody(tabs[i], colors),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleTabBody(BrowserTab tab, ColorScheme colors) {
    final BrowserEngine engine = tab.engine;

    return ListenableBuilder(
      listenable: engine,
      child: engine.controller != null
          ? WebViewWidget(
              key: ValueKey<String>('wv_${tab.id}'),
              controller: engine.controller!,
            )
          : null,
      builder: (BuildContext context, Widget? cachedWebView) {
        Widget? overlayChild;
        if (engine.isShowingDownloadsPage) {
          overlayChild = DownloadsScreen(
            downloads: widget.downloads,
            embeddedInTab: true,
          );
        } else if (engine.isShowingStartPage) {
          overlayChild = StartPage(
            settings: widget.settings,
            isIncognito: tab.isIncognito,
            searchService: widget.searchService,
            newsService: widget.newsService,
            interests: widget.interests,
            onSelectUrl: (String input) => engine.loadUserEntry(input),
            onOpenInNewTab: (String url) => widget.tabManager.openNewTab(
              incognito: false,
              initialInput: url,
            ),
            onOpenInIncognitoTab: (String url) => widget.tabManager.openNewTab(
              incognito: true,
              initialInput: url,
            ),
            onVoiceSearch: _triggerVoiceSearch,
          );
        } else if (engine.errorMessage != null) {
          overlayChild = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.wifi_off_rounded, size: 52, color: colors.error),
                  const SizedBox(height: 14),
                  const Text(
                    'Unable to reach site',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    engine.errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: engine.goHome,
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Home'),
                      ),
                      FilledButton.icon(
                        onPressed: engine.reloadOrStop,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        if (cachedWebView == null) {
          return overlayChild ??
              Center(
                child: Text(
                  engine.currentUrl ?? '',
                  style: const TextStyle(fontSize: 15),
                ),
              );
        }

        // Keep WebViewWidget onstage (never Offstage) so Android's SurfaceTexture &
        // MediaCodec pipeline are already attached and initialized on FIRST load —
        // ensuring YouTube and HTML5 videos play immediately without needing refresh!
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            IgnorePointer(ignoring: overlayChild != null, child: cachedWebView),
            if (overlayChild != null)
              ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: overlayChild,
              ),
          ],
        );
      },
    );
  }

  Widget _buildOmniboxOverlayPanel(
    BuildContext context,
    ColorScheme colors,
    BrowserEngine engine, {
    required bool showLinkActions,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String editableLink = _editableLinkForEngine(engine);
    final String shareLink = _shareableLinkForEngine(engine);

    return Material(
      elevation: 10,
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showLinkActions)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SiteLogo(
                          urlOrDomain: engine.currentUrl,
                          fallbackLabel: engine.pageTitle,
                          size: 24,
                          borderRadius: 6,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                engine.pageTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                editableLink,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _LinkActionButton(
                            icon: Icons.copy_rounded,
                            label: 'Copy',
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: shareLink),
                              );
                              _closeOmniboxOverlay();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _LinkActionButton(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            onTap: _populateCurrentUrlForEditing,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _LinkActionButton(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            onTap: () {
                              _closeOmniboxOverlay();
                              SharePlus.instance.share(
                                ShareParams(
                                  text: shareLink,
                                  subject: engine.pageTitle,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (showLinkActions &&
                (_liveSuggestions.isNotEmpty ||
                    (!widget.tabManager.isActiveIncognito &&
                        widget.settings
                            .matchingRecentSearches(_omniboxController.text)
                            .isNotEmpty)))
              const Divider(height: 1),
            if (!widget.tabManager.isActiveIncognito)
              Builder(
                builder: (BuildContext context) {
                  final List<String> recents = widget.settings
                      .matchingRecentSearches(
                        _omniboxController.text,
                        limit: 5,
                      );
                  if (recents.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
                        child: Row(
                          children: <Widget>[
                            Text(
                              'Recent Searches',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: widget.settings.clearRecentSearches,
                              child: const Text(
                                'Clear',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final String r in recents)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.history_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                          title: Text(
                            r,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.north_west_rounded,
                                  size: 16,
                                ),
                                onPressed: () {
                                  _omniboxController.text = r;
                                  _omniboxController.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(offset: r.length),
                                      );
                                  _onOmniboxTextChanged(r);
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () =>
                                    widget.settings.removeRecentSearch(r),
                              ),
                            ],
                          ),
                          onTap: () => _submitOmnibox(r),
                        ),
                      if (_liveSuggestions.isNotEmpty) const Divider(height: 1),
                    ],
                  );
                },
              ),
            for (final String suggestion in _liveSuggestions)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                title: Text(
                  suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.north_west_rounded, size: 16),
                  onPressed: () {
                    _omniboxController.text = suggestion;
                    _omniboxController.selection = TextSelection.fromPosition(
                      TextPosition(offset: suggestion.length),
                    );
                    _onOmniboxTextChanged(suggestion);
                  },
                ),
                onTap: () => _submitOmnibox(suggestion),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandCapsuleBar(
    BuildContext context,
    ColorScheme colors,
    BrowserEngine engine,
  ) {
    final bool incognito = widget.tabManager.isActiveIncognito;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isEditingOmnibox) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: incognito
              ? const Color(0xFF061015)
              : (isDark ? AppTheme.deepNavyBg : Colors.white),
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Container(
          key: const Key('wide_editing_omnibox_container'),
          height: 46,
          decoration: BoxDecoration(
            color: incognito
                ? const Color(0xFF0D1B22)
                : (isDark
                      ? AppTheme.navySurface
                      : colors.surfaceContainerHighest.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: colors.primary, width: 1.6),
          ),
          child: _buildWideEditingField(colors, engine),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: incognito
            ? const Color(0xFF061015)
            : (isDark ? AppTheme.deepNavyBg : Colors.white),
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: engine.isShowingStartPage ? null : engine.goHome,
            icon: const Icon(Icons.home_rounded, size: 20),
            tooltip: 'Home',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
          ),
          if (engine.canGoForward)
            IconButton(
              onPressed: engine.goForward,
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              tooltip: 'Forward',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
            ),
          const SizedBox(width: 2),
          Expanded(
            child: GestureDetector(
              key: const Key('top_bar_tab_swipe_detector'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                _topBarSwipeDx = 0.0;
              },
              onHorizontalDragUpdate: (DragUpdateDetails d) {
                _topBarSwipeDx += d.delta.dx;
              },
              onHorizontalDragEnd: _handleTopBarHorizontalEnd,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: incognito
                      ? const Color(0xFF0D1B22)
                      : (isDark
                            ? AppTheme.navySurface
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.65,
                              )),
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: _buildDisplayPill(context, colors, engine, incognito),
              ),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onLongPress: () => widget.tabManager.openNewTab(incognito: true),
            child: IconButton(
              key: const Key('bar_new_tab_button'),
              onPressed: () =>
                  widget.tabManager.openNewTab(incognito: incognito),
              icon: const Icon(Icons.add_rounded, size: 21),
              tooltip: 'New Tab',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: _openTabsScreen,
            onLongPress: () =>
                widget.tabManager.openNewTab(incognito: incognito),
            child: Tooltip(
              message: 'Switch Tabs',
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: incognito
                        ? AppTheme.incognitoCyan
                        : colors.primary.withValues(alpha: 0.85),
                    width: 1.8,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      '${widget.tabManager.totalTabCount}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: incognito
                            ? AppTheme.incognitoCyan
                            : colors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              widget.downloads,
              widget.vpn,
            ]),
            builder: (BuildContext context, _) {
              final bool showDot =
                  widget.downloads.hasActiveDownloads || widget.vpn.isConnected;
              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  IconButton(
                    onPressed: () => _openBrowserMenu(context),
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    tooltip: 'Browser Menu',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                  ),
                  if (showDot)
                    Positioned(
                      right: 5,
                      top: 6,
                      child: Container(
                        width: 7.5,
                        height: 7.5,
                        decoration: const BoxDecoration(
                          color: AppTheme.shieldEmerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWideEditingField(ColorScheme colors, BrowserEngine engine) {
    final bool hasText = _omniboxController.text.isNotEmpty;
    final bool showMic = !engine.isShowingWebPage && !hasText;

    return Row(
      children: <Widget>[
        IconButton(
          onPressed: _closeOmniboxOverlay,
          icon: const Icon(Icons.arrow_back_rounded, size: 19),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
          tooltip: 'Cancel',
        ),
        SearchEngineChipButton(
          currentEngine: widget.settings.searchEngine,
          onSelected: (SearchEngine sel) =>
              widget.settings.setSearchEngine(sel),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            key: const Key('top_omnibox_textfield'),
            controller: _omniboxController,
            focusNode: _omniboxFocusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onOmniboxTextChanged,
            onSubmitted: _submitOmnibox,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText:
                  'Search ${widget.settings.searchEngine.shortLabel} or enter URL',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (showMic)
          IconButton(
            onPressed: _triggerVoiceSearch,
            icon: Icon(Icons.mic_rounded, size: 19, color: colors.primary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
            tooltip: 'Voice Search',
          ),
        if (hasText) ...<Widget>[
          IconButton(
            onPressed: () {
              _omniboxController.clear();
              setState(() => _liveSuggestions = <String>[]);
            },
            icon: const Icon(Icons.cancel_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
            tooltip: 'Clear',
          ),
          IconButton(
            onPressed: _submitOmnibox,
            icon: Icon(Icons.search_rounded, size: 20, color: colors.primary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            tooltip: 'Go',
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildDisplayPill(
    BuildContext context,
    ColorScheme colors,
    BrowserEngine engine,
    bool incognito,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 3),
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 88),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SearchEngineChipButton(
                currentEngine: widget.settings.searchEngine,
                onSelected: (SearchEngine sel) =>
                    widget.settings.setSearchEngine(sel),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: widget.vpn,
          builder: (BuildContext context, _) {
            final bool vpnUp = widget.vpn.isConnected;
            return InkWell(
              key: const Key('site_permissions_button'),
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                SiteControlsSheet.show(
                  context,
                  engine: engine,
                  settings: widget.settings,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Icon(
                  vpnUp
                      ? Icons.vpn_lock_rounded
                      : (incognito
                            ? Icons.shield_moon_rounded
                            : (engine.isShowingDownloadsPage
                                  ? Icons.download_done_rounded
                                  : (engine.isShowingStartPage
                                        ? Icons.tune_rounded
                                        : (engine.isSecure
                                              ? Icons.lock_outline_rounded
                                              : Icons.warning_amber_rounded)))),
                  size: 15.5,
                  color: vpnUp
                      ? AppTheme.shieldEmerald
                      : (incognito
                            ? AppTheme.incognitoCyan
                            : (engine.isShowingStartPage ||
                                      engine.isShowingDownloadsPage
                                  ? colors.primary
                                  : (engine.isSecure
                                        ? AppTheme.shieldEmerald
                                        : AppTheme.warningAmber))),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: GestureDetector(
            key: const Key('omnibox_display_pill'),
            behavior: HitTestBehavior.opaque,
            onTap: _beginOmniboxEdit,
            child: Text(
              engine.isShowingStartPage
                  ? 'Search ${widget.settings.searchEngine.shortLabel} or type URL'
                  : OmniboxParser.formatDisplayUrl(engine.currentUrl),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: engine.isShowingStartPage
                    ? FontWeight.w400
                    : FontWeight.w600,
                color: engine.isShowingStartPage
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
          ),
        ),
        if (engine.isShowingStartPage) ...<Widget>[
          IconButton(
            onPressed: _triggerVoiceSearch,
            icon: Icon(Icons.mic_rounded, size: 18, color: colors.primary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
            tooltip: 'Voice Search',
          ),
          const SizedBox(width: 2),
        ] else
          const SizedBox(width: 5),
      ],
    );
  }

  Widget _buildFindBar(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Row(
        children: <Widget>[
          const Icon(Icons.find_in_page_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (String text) async {
                final int count = await _activeEngine.findInPage(text);
                if (mounted) {
                  setState(() => _findMatches = count);
                }
              },
              onSubmitted: (String text) async {
                final int count = await _activeEngine.findInPage(text);
                if (mounted) {
                  setState(() => _findMatches = count);
                }
              },
              decoration: const InputDecoration(
                hintText: 'Find in page...',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_findController.text.isNotEmpty)
            Text(
              '$_findMatches found',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          IconButton(
            onPressed: () {
              _findController.clear();
              setState(() {
                _showFindBar = false;
                _findMatches = 0;
              });
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _openTabsScreen() async {
    await widget.tabManager.captureTabPreview(widget.tabManager.activeTab);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TabsScreen(tabManager: widget.tabManager),
      ),
    );
  }

  void _openLibraryScreen({required int initialTabIndex}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(
          settings: widget.settings,
          initialTabIndex: initialTabIndex,
          onSelectUrl: (String url) => _activeEngine.loadUserEntry(url),
          onOpenInNewTab: (String url) =>
              widget.tabManager.openNewTab(incognito: false, initialInput: url),
          onOpenInIncognitoTab: (String url) =>
              widget.tabManager.openNewTab(incognito: true, initialInput: url),
        ),
      ),
    );
  }

  void _openVpnScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HeavenVpnScreen(vpn: widget.vpn)),
    );
  }

  Future<void> _triggerReaderMode() async {
    final ReadableArticle? article = await _activeEngine
        .extractReadableArticle();
    if (!mounted) {
      return;
    }
    if (article == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No readable article body detected on this page'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderModeSheet(article: article),
    );
  }

  Future<void> _confirmAndBurnAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.local_fire_department_rounded,
            color: AppTheme.fireCrimson,
            size: 36,
          ),
          title: const Text('Burn All Browsing Data?'),
          content: const Text(
            'Closes all open tabs and wipes cookies, cache, local storage, and browsing history immediately.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.fireCrimson,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Burn Now'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.tabManager.burnAllSessionsAndData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All tabs, cookies, storage & history burned'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openBrowserMenu(BuildContext context) async {
    final BrowserEngine engine = _activeEngine;
    final String? url = engine.currentUrl;
    final bool hasWebPage = url != null && engine.isShowingWebPage;
    final bool bookmarked = widget.settings.isBookmarked(url);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ColorScheme colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Back',
                        onPressed: engine.canGoBack
                            ? () {
                                Navigator.pop(sheetContext);
                                engine.goBack();
                              }
                            : null,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        onPressed: engine.canGoForward
                            ? () {
                                Navigator.pop(sheetContext);
                                engine.goForward();
                              }
                            : null,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      IconButton(
                        tooltip: bookmarked
                            ? 'Remove Bookmark'
                            : 'Bookmark Page',
                        onPressed: hasWebPage
                            ? () async {
                                Navigator.pop(sheetContext);
                                final bool saved = await widget.settings
                                    .toggleBookmark(
                                      url: url,
                                      title: engine.pageTitle,
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        saved
                                            ? 'Saved to Bookmarks'
                                            : 'Removed from Bookmarks',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: Icon(
                          bookmarked
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: bookmarked ? AppTheme.warningAmber : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reload',
                        onPressed: hasWebPage
                            ? () {
                                Navigator.pop(sheetContext);
                                engine.reloadOrStop();
                              }
                            : null,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        tooltip: 'Burn All Data',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _confirmAndBurnAll();
                        },
                        icon: const Icon(
                          Icons.local_fire_department_rounded,
                          color: AppTheme.fireCrimson,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 72,
                        ),
                    itemCount: 8,
                    itemBuilder: (BuildContext _, int idx) {
                      return switch (idx) {
                        0 => _DeckActionTile(
                          icon: widget.vpn.isConnected
                              ? Icons.vpn_lock_rounded
                              : Icons.vpn_key_outlined,
                          label: widget.vpn.isConnected ? 'VPN: ON' : 'VPN',
                          accent: widget.vpn.isConnected
                              ? AppTheme.shieldEmerald
                              : colors.primary,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openVpnScreen();
                          },
                        ),
                        1 => _DeckActionTile(
                          icon: Icons.shield_moon_outlined,
                          label: 'Incognito',
                          accent: AppTheme.incognitoCyan,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            widget.tabManager.openNewTab(incognito: true);
                          },
                        ),
                        2 => _DeckActionTile(
                          icon: Icons.bookmarks_outlined,
                          label: 'Bookmarks',
                          accent: AppTheme.warningAmber,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openLibraryScreen(initialTabIndex: 0);
                          },
                        ),
                        3 => _DeckActionTile(
                          icon: Icons.history_rounded,
                          label: 'History',
                          accent: colors.primary,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openLibraryScreen(initialTabIndex: 1);
                          },
                        ),
                        4 => _DeckActionTile(
                          tileKey: const Key('browser_menu_downloads_tile'),
                          icon: Icons.download_rounded,
                          label: widget.downloads.activeCount > 0
                              ? 'Downloads (${widget.downloads.activeCount})'
                              : 'Downloads',
                          accent: AppTheme.shieldEmerald,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openDownloadsTab();
                          },
                        ),
                        5 => _DeckActionTile(
                          icon: Icons.tune_rounded,
                          label: 'Permissions',
                          accent: colors.primary,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            SiteControlsSheet.show(
                              context,
                              engine: engine,
                              settings: widget.settings,
                            );
                          },
                        ),
                        6 => _DeckActionTile(
                          icon: Icons.menu_book_rounded,
                          label: 'Reader',
                          accent: colors.primary,
                          enabled: hasWebPage,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _triggerReaderMode();
                          },
                        ),
                        _ => _DeckActionTile(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          accent: colors.primary,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SettingsScreen(
                                  settings: widget.settings,
                                  tabManager: widget.tabManager,
                                  downloads: widget.downloads,
                                ),
                              ),
                            );
                          },
                        ),
                      };
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('browser_menu_inspect_tile'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.developer_mode_rounded,
                      size: 20,
                      color: _showInspectorPanel
                          ? AppTheme.shieldEmerald
                          : colors.primary,
                    ),
                    title: const Text('Inspect (DevTools)'),
                    subtitle: const Text(
                      'Desktop DOM Elements, Console, Network & Storage',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      _showInspectorPanel ? 'OPEN' : 'F12',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _showInspectorPanel
                            ? AppTheme.shieldEmerald
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(
                        () => _showInspectorPanel = !_showInspectorPanel,
                      );
                    },
                  ),
                  if (hasWebPage)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(
                        Icons.find_in_page_outlined,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: const Text('Find in page'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _showFindBar = true);
                      },
                    ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Site Permission Dashboard'),
                    subtitle: const Text(
                      'Location, Camera, Mic & 1-tap revoke',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      SiteControlsSheet.show(
                        context,
                        engine: engine,
                        settings: widget.settings,
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.workspaces_outline,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Add tab to new group'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      TabsScreen.showCreateGroupDialog(
                        context,
                        tabManager: widget.tabManager,
                        tabId: widget.tabManager.activeTab.id,
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.add_to_home_screen_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Create shortcut'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _createShortcutForCurrentPage(context, engine);
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Notifications'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NotificationsScreen(settings: widget.settings),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.translate_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Languages'),
                    trailing: Text(
                      widget.settings.language.nativeLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              LanguagesScreen(settings: widget.settings),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    key: const Key('browser_menu_privacy_policy_tile'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.privacy_tip_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      widget.tabManager.openNewTab(
                        incognito: widget.tabManager.isActiveIncognito,
                        initialInput: AppConstants.privacyPolicyUrl,
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    title: const Text('Help'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HelpScreen(
                            onOpenUrlInBrowser: (String url) =>
                                widget.tabManager.openNewTab(
                                  incognito: widget.tabManager.isActiveIncognito,
                                  initialInput: url,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    dense: true,
                    secondary: const Icon(Icons.desktop_windows_outlined),
                    title: const Text('Desktop Site'),
                    subtitle: const Text('Full 1280px desktop layout'),
                    value: widget.settings.desktopMode,
                    onChanged: (bool value) async {
                      Navigator.pop(sheetContext);
                      await engine.setDesktopModeAndReload(value);
                    },
                  ),
                  if (hasWebPage)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.share_outlined, size: 20),
                      title: const Text(
                        'Share Link',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Download Current URL',
                            icon: const Icon(Icons.download_outlined, size: 19),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              widget.downloads.startUrlDownload(url: url);
                            },
                          ),
                          IconButton(
                            tooltip: 'Copy Link',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              await Clipboard.setData(ClipboardData(text: url));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URL copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Open externally',
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              final Uri? parsed = Uri.tryParse(url);
                              if (parsed != null) {
                                await launchUrl(
                                  parsed,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        SharePlus.instance.share(
                          ShareParams(text: url, subject: engine.pageTitle),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createShortcutForCurrentPage(
    BuildContext context,
    BrowserEngine engine,
  ) async {
    final String initialUrl =
        (engine.currentUrl != null &&
            (engine.currentUrl!.startsWith('http://') ||
                engine.currentUrl!.startsWith('https://')))
        ? engine.currentUrl!
        : 'https://www.google.com';
    final String initialTitle =
        (engine.isShowingWebPage && engine.pageTitle != 'New Tab')
        ? engine.pageTitle.trim()
        : OmniboxParser.friendlySiteTitleFromDomain(
            OmniboxParser.cleanDomain(initialUrl),
          );

    final ({String title, String url})? chosen =
        await showDialog<({String title, String url})>(
          context: context,
          builder: (_) => _CreateShortcutDialog(
            initialTitle: initialTitle,
            initialUrl: initialUrl,
          ),
        );

    if (chosen == null || chosen.url.isEmpty) {
      return;
    }

    final bool sameSite =
        OmniboxParser.cleanDomain(chosen.url) ==
        OmniboxParser.cleanDomain(engine.currentUrl);
    await widget.settings.recordPageVisit(
      url: chosen.url,
      title: chosen.title.isEmpty ? chosen.url : chosen.title,
    );
    final bool pinned = await NativeShieldBridge.instance
        .createHomeScreenShortcut(
          url: chosen.url,
          title: chosen.title.isEmpty ? 'Heaven Shortcut' : chosen.title,
          iconUrl: sameSite ? engine.pageIconUrl : null,
          webViewId: sameSite ? engine.androidWebViewId : null,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pinned
                ? 'Shortcut added to Home Screen with website logo!'
                : 'Added to Heaven Quick Launch!',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _LinkActionButton extends StatelessWidget {
  const _LinkActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: colors.primary.withValues(alpha: 0.32)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckActionTile extends StatelessWidget {
  const _DeckActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.tileKey,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final Key? tileKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.38,
      child: InkWell(
        key: tileKey,
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: accent, size: 22),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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

class _CreateShortcutDialog extends StatefulWidget {
  const _CreateShortcutDialog({
    required this.initialTitle,
    required this.initialUrl,
  });

  final String initialTitle;
  final String initialUrl;

  @override
  State<_CreateShortcutDialog> createState() => _CreateShortcutDialogState();
}

class _CreateShortcutDialogState extends State<_CreateShortcutDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _urlCtrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: <Widget>[
          SiteLogo(
            urlOrDomain: _urlCtrl.text,
            fallbackLabel: _titleCtrl.text,
            size: 36,
            borderRadius: 10,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Create Shortcut')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Shortcut Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Website URL',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, (
            title: _titleCtrl.text.trim(),
            url: _urlCtrl.text.trim(),
          )),
          icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
          label: const Text('Add Shortcut'),
        ),
      ],
    );
  }
}
