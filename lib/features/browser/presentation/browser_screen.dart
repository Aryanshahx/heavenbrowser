import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../../core/widgets/site_logo.dart';
import '../../downloads/downloads_controller.dart';
import '../../downloads/downloads_screen.dart';
import '../../news/interest_news_service.dart';
import '../../search/heaven_search_service.dart';
import '../../search/heaven_search_view.dart';
import '../../settings/browser_settings.dart';
import '../../settings/settings_screen.dart';
import '../../shield/native_shield_bridge.dart';
import '../../tabs/tab_manager.dart';
import '../../tabs/tabs_screen.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_screen.dart';
import '../engine/browser_engine.dart';
import 'widgets/library_screen.dart';
import 'widgets/reader_mode_sheet.dart';
import 'widgets/shield_sheet.dart';
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
  List<String> _liveSuggestions = <String>[];
  bool _isEditingOmnibox = false;
  bool _showLinkActionsCard = false;
  bool _showFindBar = false;
  int _findMatches = 0;

  BrowserEngine get _activeEngine => widget.tabManager.activeEngine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.downloads.onDownloadToast = (String msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Downloads',
            onPressed: _openDownloadsScreen,
          ),
        ),
      );
    };
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    if (widget.downloads.onDownloadToast != null) {
      widget.downloads.onDownloadToast = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _omniboxController.dispose();
    _omniboxFocusNode.dispose();
    _findController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.settings.clearOnExit) {
      unawaited(widget.tabManager.burnAllSessionsAndData());
    }
  }

  String _editableLinkForEngine(BrowserEngine engine) {
    final String? url = engine.currentUrl;
    if (OmniboxParser.isHeavenSearchUrl(url)) {
      return OmniboxParser.extractHeavenQuery(url);
    }
    final String googleQ = OmniboxParser.extractGoogleSearchQuery(url);
    if (googleQ.isNotEmpty) {
      return googleQ;
    }
    return url ?? '';
  }

  String _shareableLinkForEngine(BrowserEngine engine) {
    final String? url = engine.currentUrl;
    if (OmniboxParser.isHeavenSearchUrl(url)) {
      final String q = OmniboxParser.extractHeavenQuery(url);
      return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';
    }
    return url ?? '';
  }

  void _beginOmniboxEdit() {
    final bool hasActiveLink = !_activeEngine.isShowingStartPage;
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
    // Hide Copy/Edit/Share card and keep wide full-width bar open for easy URL editing!
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
    if (!widget.tabManager.isActiveIncognito) {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.tabManager,
        widget.settings,
        widget.downloads,
        widget.vpn,
      ]),
      builder: (BuildContext context, _) {
        final bool incognito = widget.tabManager.isActiveIncognito;
        final ThemeData effectiveTheme = incognito
            ? AppTheme.incognitoTheme
            : Theme.of(context);
        final ColorScheme colors = effectiveTheme.colorScheme;
        final bool bottomBar = widget.settings.bottomOmnibox;
        final BrowserEngine engine = _activeEngine;
        final bool showLinkActions =
            _isEditingOmnibox &&
            _showLinkActionsCard &&
            !engine.isShowingStartPage;
        final bool showOverlayPanel =
            showLinkActions ||
            (_isEditingOmnibox && _liveSuggestions.isNotEmpty);

        return Theme(
          data: effectiveTheme,
          child: PopScope<void>(
            canPop:
                !engine.canGoBack &&
                !_isEditingOmnibox &&
                !_showLinkActionsCard &&
                !_showFindBar,
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
              if (engine.canGoBack) {
                await engine.goBack();
              }
            },
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: <Widget>[
                    // TOP DOCK BAR BY DEFAULT
                    if (!bottomBar) _buildCommandCapsuleBar(context, colors),
                    if (_showFindBar) _buildFindBar(colors),
                    if (engine.isLoading)
                      LinearProgressIndicator(
                        value: engine.progress > 0 && engine.progress < 1
                            ? engine.progress
                            : null,
                        minHeight: 2.5,
                        backgroundColor: Colors.transparent,
                      ),
                    Expanded(
                      child: Stack(
                        children: <Widget>[
                          _buildTabsViewport(colors),
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
                          // Full-screen tap-anywhere barrier so tapping outside Copy/Edit/Share
                          // or outside the editing bar dismisses it immediately (even over WebView)!
                          if (_isEditingOmnibox || _showLinkActionsCard)
                            Positioned.fill(
                              child: GestureDetector(
                                key: const Key('omnibox_outside_dismiss_scrim'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeOmniboxOverlay,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                          if (showOverlayPanel)
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: bottomBar ? 8 : null,
                              top: bottomBar ? null : 8,
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
                    if (bottomBar) _buildCommandCapsuleBar(context, colors),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
        for (final BrowserTab tab in tabs)
          KeyedSubtree(
            key: ValueKey<String>(tab.id),
            child: RepaintBoundary(
              key: tab.repaintKey,
              child: _buildSingleTabBody(tab, colors),
            ),
          ),
      ],
    );
  }

  Widget _buildSingleTabBody(BrowserTab tab, ColorScheme colors) {
    final BrowserEngine engine = tab.engine;

    if (engine.isShowingStartPage) {
      return StartPage(
        settings: widget.settings,
        isIncognito: tab.isIncognito,
        searchService: widget.searchService,
        newsService: widget.newsService,
        interests: widget.interests,
        onSelectUrl: (String input) => engine.loadUserEntry(input),
        onOpenInNewTab: (String url) =>
            widget.tabManager.openNewTab(incognito: false, initialInput: url),
        onOpenInIncognitoTab: (String url) =>
            widget.tabManager.openNewTab(incognito: true, initialInput: url),
        onVoiceSearch: _triggerVoiceSearch,
      );
    }

    if (engine.isShowingHeavenSearch) {
      return HeavenSearchView(
        query: engine.heavenSearchQuery,
        searchService: widget.searchService,
        downloads: widget.downloads,
        isIncognito: tab.isIncognito,
        onOpenUrl: (String url) {
          if (!tab.isIncognito) {
            unawaited(widget.interests.recordActivity(text: url, weight: 1.4));
          }
          engine.loadUserEntry(url);
        },
        onOpenInNewTab: (String url) =>
            widget.tabManager.openNewTab(incognito: false, initialInput: url),
        onOpenInIncognitoTab: (String url) =>
            widget.tabManager.openNewTab(incognito: true, initialInput: url),
        onSubmitNewQuery: (String q) {
          if (!tab.isIncognito) {
            unawaited(widget.interests.recordActivity(text: q, weight: 2.2));
          }
          engine.loadUri(Uri.parse(SearchEngine.heaven.buildSearchUrl(q)));
        },
        onVoiceSearch: _triggerVoiceSearch,
      );
    }

    if (engine.errorMessage != null) {
      return Center(
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

    if (engine.controller == null) {
      return Center(
        child: Text(
          engine.currentUrl ?? '',
          style: const TextStyle(fontSize: 15),
        ),
      );
    }

    return WebViewWidget(controller: engine.controller!);
  }

  /// Overlay card shown when tapping the address/search bar on an active link:
  /// - Shows Copy, Edit, Share options!
  /// - Disappears immediately when tapping anywhere outside or tapping Edit!
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
                                engine.isShowingHeavenSearch
                                    ? 'Search: ${engine.heavenSearchQuery}'
                                    : engine.pageTitle,
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
            if (showLinkActions && _liveSuggestions.isNotEmpty)
              const Divider(height: 1),
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

  /// Responsive Top/Bottom Dock Bar:
  /// - When `_isEditingOmnibox` is true: Expands Search/URL bar across FULL WIDTH for easy link editing!
  /// - When displaying normally: `[Home] [Forward?] [Shield | Search/URL Pill] [+ New Tab] [Tabs] [Menu]`!
  Widget _buildCommandCapsuleBar(BuildContext context, ColorScheme colors) {
    final BrowserEngine engine = _activeEngine;
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
            top: widget.settings.bottomOmnibox
                ? BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  )
                : BorderSide.none,
            bottom: !widget.settings.bottomOmnibox
                ? BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  )
                : BorderSide.none,
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
          top: widget.settings.bottomOmnibox
              ? BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35))
              : BorderSide.none,
          bottom: !widget.settings.bottomOmnibox
              ? BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35))
              : BorderSide.none,
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
          const SizedBox(width: 2),
          // + Button right in the search bar area to add more tabs!
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
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                onPressed: () => _openBrowserMenu(context),
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                tooltip: 'Browser Menu',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              ),
              if (widget.downloads.hasActiveDownloads || widget.vpn.isConnected)
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
          ),
        ],
      ),
    );
  }

  /// Full-width wide search/URL editing field (shown when tapping the search bar or tapping Edit!)
  Widget _buildWideEditingField(ColorScheme colors, BrowserEngine engine) {
    final bool hasText = _omniboxController.text.isNotEmpty;
    // Only show Mic when on Start Page AND nothing searched/typed!
    final bool showMic = engine.isShowingStartPage && !hasText;

    return Row(
      children: <Widget>[
        IconButton(
          onPressed: _closeOmniboxOverlay,
          icon: const Icon(Icons.arrow_back_rounded, size: 19),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: 'Cancel',
        ),
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
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openShieldSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Icon(
              widget.vpn.isConnected
                  ? Icons.vpn_lock_rounded
                  : (incognito
                        ? Icons.shield_moon_rounded
                        : (engine.isShowingStartPage
                              ? Icons.shield_outlined
                              : (engine.isSecure
                                    ? Icons.lock_outline_rounded
                                    : Icons.warning_amber_rounded))),
              size: 16.5,
              color: widget.vpn.isConnected
                  ? AppTheme.shieldEmerald
                  : (incognito
                        ? AppTheme.incognitoCyan
                        : (engine.isShowingStartPage
                              ? colors.primary
                              : (engine.isSecure
                                    ? AppTheme.shieldEmerald
                                    : AppTheme.warningAmber))),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            key: const Key('omnibox_display_pill'),
            behavior: HitTestBehavior.opaque,
            onTap: _beginOmniboxEdit,
            child: Text(
              engine.isShowingStartPage
                  ? 'Search or type URL'
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
        if (engine.pageBlockedCount > 0)
          GestureDetector(
            onTap: () => _openShieldSheet(context),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.shieldEmerald.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${engine.pageBlockedCount}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.shieldEmerald,
                ),
              ),
            ),
          ),
        // Only show Mic when on Start Page — NEVER when we already searched something!
        if (engine.isShowingStartPage) ...<Widget>[
          IconButton(
            onPressed: _triggerVoiceSearch,
            icon: Icon(Icons.mic_rounded, size: 18.5, color: colors.primary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
            tooltip: 'Voice Search',
          ),
          const SizedBox(width: 2),
        ] else
          const SizedBox(width: 8),
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

  void _openDownloadsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadsScreen(downloads: widget.downloads),
      ),
    );
  }

  void _openVpnScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HeavenVpnScreen(vpn: widget.vpn)),
    );
  }

  Future<void> _openShieldSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShieldSheet(
        engine: _activeEngine,
        settings: widget.settings,
        vpn: widget.vpn,
        onOpenVpnScreen: _openVpnScreen,
      ),
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
    final bool hasWebPage =
        url != null &&
        !engine.isShowingStartPage &&
        !engine.isShowingHeavenSearch;
    final bool bookmarked = widget.settings.isBookmarked(url);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final ColorScheme colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
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
                        onPressed: !engine.isShowingStartPage
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
                          icon: Icons.download_rounded,
                          label: widget.downloads.activeCount > 0
                              ? 'Downloads (${widget.downloads.activeCount})'
                              : 'Downloads',
                          accent: AppTheme.shieldEmerald,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openDownloadsScreen();
                          },
                        ),
                        5 => _DeckActionTile(
                          icon: Icons.menu_book_rounded,
                          label: 'Reader',
                          accent: colors.primary,
                          enabled: hasWebPage,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _triggerReaderMode();
                          },
                        ),
                        6 => _DeckActionTile(
                          icon: Icons.find_in_page_outlined,
                          label: 'Find Text',
                          accent: colors.primary,
                          enabled: hasWebPage,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            setState(() => _showFindBar = true);
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
                                ),
                              ),
                            );
                          },
                        ),
                      };
                    },
                  ),
                  const SizedBox(height: 8),
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
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.38,
      child: InkWell(
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
