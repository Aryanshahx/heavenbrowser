import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/omnibox_parser.dart';
import '../../search/heaven_search_service.dart';
import '../../search/heaven_search_view.dart';
import '../../settings/browser_settings.dart';
import '../../settings/settings_screen.dart';
import '../../tabs/tab_manager.dart';
import '../../tabs/tab_switcher_sheet.dart';
import '../engine/browser_engine.dart';
import 'widgets/library_sheet.dart';
import 'widgets/reader_mode_sheet.dart';
import 'widgets/shield_sheet.dart';
import 'widgets/start_page.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.settings,
    required this.tabManager,
    required this.searchService,
  });

  final BrowserSettingsController settings;
  final TabManagerController tabManager;
  final HeavenSearchService searchService;

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
  bool _showFindBar = false;
  int _findMatches = 0;

  BrowserEngine get _activeEngine => widget.tabManager.activeEngine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _omniboxFocusNode.addListener(_handleOmniboxFocusChange);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _omniboxFocusNode.removeListener(_handleOmniboxFocusChange);
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

  void _handleOmniboxFocusChange() {
    if (!_omniboxFocusNode.hasFocus && _isEditingOmnibox) {
      setState(() {
        _isEditingOmnibox = false;
        _liveSuggestions = <String>[];
      });
    }
  }

  void _beginOmniboxEdit() {
    final String? url = _activeEngine.currentUrl;
    if (OmniboxParser.isHeavenSearchUrl(url)) {
      _omniboxController.text = OmniboxParser.extractHeavenQuery(url);
    } else {
      _omniboxController.text = url ?? '';
    }
    _omniboxController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _omniboxController.text.length,
    );
    setState(() {
      _isEditingOmnibox = true;
      _liveSuggestions = <String>[];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _omniboxFocusNode.requestFocus();
      }
    });
  }

  void _onOmniboxTextChanged(String text) {
    _suggestDebounce?.cancel();
    final String trimmed = text.trim();
    if (trimmed.length < 2) {
      if (_liveSuggestions.isNotEmpty) {
        setState(() => _liveSuggestions = <String>[]);
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 180), () async {
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
    _suggestDebounce?.cancel();
    _omniboxFocusNode.unfocus();
    setState(() {
      _isEditingOmnibox = false;
      _liveSuggestions = <String>[];
    });
    if (raw.isEmpty) {
      return;
    }
    await _activeEngine.loadUserEntry(raw);
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
        final bool bottomBar = widget.settings.bottomOmnibox;
        final BrowserEngine engine = _activeEngine;

        return Theme(
          data: effectiveTheme,
          child: PopScope<void>(
            canPop: !engine.canGoBack && !_isEditingOmnibox && !_showFindBar,
            onPopInvokedWithResult: (bool didPop, void _) async {
              if (didPop) {
                return;
              }
              if (_isEditingOmnibox) {
                _omniboxFocusNode.unfocus();
                setState(() {
                  _isEditingOmnibox = false;
                  _liveSuggestions = <String>[];
                });
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
                          if (_isEditingOmnibox && _liveSuggestions.isNotEmpty)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: bottomBar ? 8 : null,
                              top: bottomBar ? null : 8,
                              child: _buildAutocompleteCard(colors),
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

  Widget _buildTabsViewport(ColorScheme colors) {
    final List<BrowserTab> tabs = widget.tabManager.allTabs;
    final int activeIndex = widget.tabManager.activeTabIndex;

    return IndexedStack(
      index: activeIndex,
      children: <Widget>[
        for (final BrowserTab tab in tabs)
          KeyedSubtree(
            key: ValueKey<String>(tab.id),
            child: _buildSingleTabBody(tab, colors),
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
        onSelectUrl: (String input) => engine.loadUserEntry(input),
        onOpenInNewTab: (String url) =>
            widget.tabManager.openNewTab(incognito: false, initialInput: url),
        onOpenInIncognitoTab: (String url) =>
            widget.tabManager.openNewTab(incognito: true, initialInput: url),
        onTapSearchBox: _beginOmniboxEdit,
        onOpenBookmarks: () => _openLibrarySheet(initialTabIndex: 0),
        onOpenHistory: () => _openLibrarySheet(initialTabIndex: 1),
        onToggleIncognitoNewTab: () {
          if (tab.isIncognito) {
            final List<BrowserTab> normals = widget.tabManager.normalTabs;
            if (normals.isNotEmpty) {
              widget.tabManager.switchToTab(normals.last.id);
            } else {
              widget.tabManager.openNewTab(incognito: false);
            }
          } else {
            final List<BrowserTab> incogs = widget.tabManager.incognitoTabs;
            if (incogs.isNotEmpty) {
              widget.tabManager.switchToTab(incogs.last.id);
            } else {
              widget.tabManager.openNewTab(incognito: true);
            }
          }
        },
      );
    }

    if (engine.isShowingHeavenSearch) {
      return HeavenSearchView(
        query: engine.heavenSearchQuery,
        searchService: widget.searchService,
        isIncognito: tab.isIncognito,
        onOpenUrl: (String url) => engine.loadUserEntry(url),
        onOpenInNewTab: (String url) =>
            widget.tabManager.openNewTab(incognito: false, initialInput: url),
        onOpenInIncognitoTab: (String url) =>
            widget.tabManager.openNewTab(incognito: true, initialInput: url),
        onSubmitNewQuery: (String q) =>
            engine.loadUri(Uri.parse(SearchEngine.heaven.buildSearchUrl(q))),
      );
    }

    if (engine.errorMessage != null) {
      return Center(
        child: Padding(
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
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: engine.goHome,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Start Deck'),
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

  Widget _buildAutocompleteCard(ColorScheme colors) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 10,
      color: isDark ? const Color(0xFF10192E) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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

  Widget _buildCommandCapsuleBar(BuildContext context, ColorScheme colors) {
    final BrowserEngine engine = _activeEngine;
    final bool incognito = widget.tabManager.isActiveIncognito;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String? url = engine.currentUrl;
    final bool canBookmark =
        url != null &&
        !engine.isShowingStartPage &&
        !engine.isShowingHeavenSearch;
    final bool bookmarked = widget.settings.isBookmarked(url);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: incognito
            ? const Color(0xFF0E061B)
            : (isDark ? const Color(0xFF080D1B) : Colors.white),
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
            onPressed: engine.canGoBack ? engine.goBack : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: incognito
                    ? const Color(0xFF1B0F30)
                    : (isDark
                          ? const Color(0xFF121C33)
                          : colors.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            )),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _isEditingOmnibox
                      ? colors.primary
                      : colors.outlineVariant.withValues(alpha: 0.4),
                  width: _isEditingOmnibox ? 1.5 : 1,
                ),
              ),
              child: _isEditingOmnibox
                  ? _buildEditingField(colors)
                  : _buildDisplayPill(
                      context,
                      colors,
                      engine,
                      incognito,
                      canBookmark,
                      bookmarked,
                    ),
            ),
          ),
          const SizedBox(width: 6),
          // Multi-Tab Counter Pill
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: _openTabSwitcher,
            onLongPress: () =>
                widget.tabManager.openNewTab(incognito: incognito),
            child: Tooltip(
              message: 'Switch Tabs (Hold for New Tab)',
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: incognito
                        ? AppTheme.incognitoOrchid
                        : colors.primary.withValues(alpha: 0.8),
                    width: 1.8,
                  ),
                ),
                child: Text(
                  '${widget.tabManager.totalTabCount}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: incognito
                        ? AppTheme.incognitoOrchid
                        : colors.primary,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _openCommandDeck(context),
            icon: const Icon(Icons.grid_view_rounded, size: 21),
            tooltip: 'Command Deck',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEditingField(ColorScheme colors) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 12),
        Icon(Icons.search_rounded, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _omniboxController,
            focusNode: _omniboxFocusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onOmniboxTextChanged,
            onSubmitted: _submitOmnibox,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Search ${widget.settings.searchEngine.shortLabel} or enter address',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (_omniboxController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _omniboxController.clear();
              setState(() => _liveSuggestions = <String>[]);
            },
            icon: const Icon(Icons.cancel_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Clear',
          ),
      ],
    );
  }

  Widget _buildDisplayPill(
    BuildContext context,
    ColorScheme colors,
    BrowserEngine engine,
    bool incognito,
    bool canBookmark,
    bool bookmarked,
  ) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openShieldSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(
              incognito
                  ? Icons.shield_moon_rounded
                  : (engine.isShowingStartPage
                        ? Icons.shield_outlined
                        : (engine.isSecure
                              ? Icons.lock_outline_rounded
                              : Icons.warning_amber_rounded)),
              size: 17,
              color: incognito
                  ? AppTheme.incognitoOrchid
                  : (engine.isShowingStartPage
                        ? colors.primary
                        : (engine.isSecure
                              ? AppTheme.shieldEmerald
                              : AppTheme.warningAmber)),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.shield_rounded,
                    size: 11,
                    color: AppTheme.shieldEmerald,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${engine.pageBlockedCount}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.shieldEmerald,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (canBookmark)
          IconButton(
            onPressed: () async {
              final bool saved = await widget.settings.toggleBookmark(
                url: engine.currentUrl!,
                title: engine.pageTitle,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      saved ? 'Saved to Bookmarks' : 'Removed from Bookmarks',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: Icon(
              bookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 19,
              color: bookmarked ? AppTheme.warningAmber : null,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: 'Bookmark page',
          ),
        if (!engine.isShowingStartPage)
          IconButton(
            onPressed: engine.reloadOrStop,
            icon: Icon(
              engine.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
              size: 18,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: engine.isLoading ? 'Stop' : 'Reload',
          )
        else
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

  Future<void> _openTabSwitcher() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TabSwitcherSheet(tabManager: widget.tabManager),
    );
  }

  Future<void> _openShieldSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ShieldSheet(engine: _activeEngine, settings: widget.settings),
    );
  }

  Future<void> _openLibrarySheet({required int initialTabIndex}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LibrarySheet(
        settings: widget.settings,
        initialTabIndex: initialTabIndex,
        onSelectUrl: (String url) => _activeEngine.loadUserEntry(url),
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

  Future<void> _openCommandDeck(BuildContext context) async {
    final BrowserEngine engine = _activeEngine;
    final String? url = engine.currentUrl;
    final bool hasWebPage =
        url != null &&
        !engine.isShowingStartPage &&
        !engine.isShowingHeavenSearch;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final ColorScheme colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Top navigation quick row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
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
                      tooltip: 'Start Deck',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        engine.goHome();
                      },
                      icon: const Icon(Icons.home_outlined),
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
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: <Widget>[
                    _DeckActionTile(
                      icon: Icons.add_box_outlined,
                      label: 'New Tab',
                      accent: colors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        widget.tabManager.openNewTab(incognito: false);
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.shield_moon_outlined,
                      label: 'Incognito',
                      accent: AppTheme.incognitoOrchid,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        widget.tabManager.openNewTab(incognito: true);
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.bookmarks_outlined,
                      label: 'Bookmarks',
                      accent: AppTheme.warningAmber,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openLibrarySheet(initialTabIndex: 0);
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.history_rounded,
                      label: 'History',
                      accent: colors.primary,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openLibrarySheet(initialTabIndex: 1);
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.menu_book_rounded,
                      label: 'Reader',
                      accent: AppTheme.shieldEmerald,
                      enabled: hasWebPage,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _triggerReaderMode();
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.find_in_page_outlined,
                      label: 'Find Text',
                      accent: colors.primary,
                      enabled: hasWebPage,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _showFindBar = true);
                      },
                    ),
                    _DeckActionTile(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      accent: colors.primary,
                      enabled: url != null && !engine.isShowingStartPage,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        SharePlus.instance.share(
                          ShareParams(text: url!, subject: engine.pageTitle),
                        );
                      },
                    ),
                    _DeckActionTile(
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
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  dense: true,
                  secondary: const Icon(Icons.desktop_windows_outlined),
                  title: const Text('Desktop Site Mode'),
                  value: widget.settings.desktopMode,
                  onChanged: (bool value) async {
                    Navigator.pop(sheetContext);
                    await widget.settings.setDesktopMode(value);
                    if (hasWebPage) {
                      await engine.reloadOrStop();
                    }
                  },
                ),
                if (hasWebPage)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copy Current Link'),
                    trailing: IconButton(
                      tooltip: 'Open externally',
                      icon: const Icon(Icons.open_in_new_rounded, size: 19),
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
                    onTap: () async {
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
              ],
            ),
          ),
        );
      },
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
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: accent, size: 23),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
