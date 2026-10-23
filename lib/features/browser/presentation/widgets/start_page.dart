import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/search_engine_chip_button.dart';
import '../../../../core/widgets/site_logo.dart';
import '../../../news/interest_news_service.dart';
import '../../../search/heaven_search_service.dart';
import '../../../settings/browser_settings.dart';

class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    required this.settings,
    required this.isIncognito,
    required this.searchService,
    required this.newsService,
    required this.interests,
    required this.onSelectUrl,
    required this.onOpenInNewTab,
    required this.onOpenInIncognitoTab,
    required this.onVoiceSearch,
  });

  final BrowserSettingsController settings;
  final bool isIncognito;
  final HeavenSearchService searchService;
  final HeavenNewsFeedService newsService;
  final InterestProfileController interests;
  final ValueChanged<String> onSelectUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final VoidCallback onVoiceSearch;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final TextEditingController _homeSearchController = TextEditingController();
  final FocusNode _homeSearchFocus = FocusNode();

  Timer? _suggestDebounce;
  List<String> _suggestions = <String>[];
  NewsCategoryTab _selectedNewsTab = NewsCategoryTab.forYou;
  List<PersonalizedNewsItem> _newsItems = const <PersonalizedNewsItem>[];
  bool _loadingNews = false;

  @override
  void initState() {
    super.initState();
    _homeSearchFocus.addListener(() {
      if (mounted) {
        setState(() {
          if (!_homeSearchFocus.hasFocus) {
            _suggestions = <String>[];
          }
        });
      }
    });
    if (!widget.isIncognito) {
      _newsItems = widget.newsService.readCached(_selectedNewsTab);
      unawaited(_refreshNews());
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _homeSearchController.dispose();
    _homeSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshNews() async {
    if (widget.isIncognito || !mounted) {
      return;
    }
    setState(() => _loadingNews = true);
    final List<PersonalizedNewsItem> fresh = await widget.newsService.fetchFeed(
      _selectedNewsTab,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _newsItems = fresh;
      _loadingNews = false;
    });
  }

  void _onSelectNewsCategory(NewsCategoryTab tab) {
    if (_selectedNewsTab == tab) {
      return;
    }
    setState(() {
      _selectedNewsTab = tab;
      _newsItems = widget.newsService.readCached(tab);
    });
    unawaited(_refreshNews());
  }

  void _onHomeSearchChanged(String raw) {
    setState(() {});
    _suggestDebounce?.cancel();
    final String trimmed = raw.trim();
    if (trimmed.length < 2) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = <String>[]);
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 180), () async {
      final List<String> fetched = await widget.searchService.fetchSuggestions(
        trimmed,
      );
      if (mounted && _homeSearchFocus.hasFocus) {
        setState(() => _suggestions = fetched);
      }
    });
  }

  void _onSearchIconTap() {
    final String query = _homeSearchController.text.trim();
    if (query.isEmpty) {
      _homeSearchFocus.requestFocus();
      return;
    }
    _submitHomeSearch(query);
  }

  void _submitHomeSearch([String? overrideValue]) {
    final String query = (overrideValue ?? _homeSearchController.text).trim();
    _suggestDebounce?.cancel();
    _homeSearchFocus.unfocus();
    setState(() => _suggestions = <String>[]);
    if (query.isEmpty) {
      return;
    }
    if (!widget.isIncognito) {
      unawaited(widget.interests.recordActivity(text: query, weight: 2.2));
    }
    _homeSearchController.clear();
    widget.onSelectUrl(query);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.settings,
        widget.interests,
      ]),
      builder: (BuildContext context, _) {
        final List<SiteUsageEntry> sites = widget.settings.quickLaunchSites;

        return RefreshIndicator(
          onRefresh: _refreshNews,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: <Widget>[
                      ShaderMask(
                        shaderCallback: (Rect bounds) =>
                            (widget.isIncognito
                                    ? AppTheme.incognitoGradient
                                    : AppTheme.brandGradient)
                                .createShader(bounds),
                        child: Text(
                          widget.isIncognito ? 'Heaven Incognito' : 'Heaven',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 34,
                            letterSpacing: -1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Working Home Screen Search Bar (Search icon submits + Keyboard Enter; Enter arrow button removed!)
                      _buildWorkingHomeSearchBar(context, colors, isDark),
                      if (_homeSearchFocus.hasFocus &&
                          (_suggestions.isNotEmpty ||
                              (!widget.isIncognito &&
                                  widget.settings
                                      .matchingRecentSearches(
                                        _homeSearchController.text,
                                      )
                                      .isNotEmpty))) ...<Widget>[
                        const SizedBox(height: 6),
                        _buildHomeSuggestionsCard(colors, isDark),
                      ],
                      if (widget.isIncognito) ...<Widget>[
                        const SizedBox(height: 22),
                        _buildIncognitoPrivacyNote(colors),
                      ],
                    ],
                  ),
                ),
              ),
              if (!widget.isIncognito && sites.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 88,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.80,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final SiteUsageEntry site = sites[index];
                      return _QuickSiteTile(
                        site: site,
                        onTap: () {
                          unawaited(
                            widget.interests.recordActivity(
                              text: '${site.title} ${site.domain}',
                              weight: 1.2,
                            ),
                          );
                          widget.onSelectUrl(site.url);
                        },
                        onLongPress: () => _showSiteMenu(context, site),
                      );
                    }, childCount: sites.length),
                  ),
                ),
              if (!widget.isIncognito) ...<Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                  sliver: SliverToBoxAdapter(
                    child: _buildNewsSectionHeader(context, colors),
                  ),
                ),
                if (_loadingNews && _newsItems.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_newsItems.isEmpty)
                  SliverToBoxAdapter(child: _buildEmptyNewsState(colors))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    sliver: SliverList.separated(
                      itemCount: _newsItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (BuildContext context, int index) {
                        return _buildGoogleDiscoverCard(
                          context,
                          colors,
                          isDark,
                          _newsItems[index],
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkingHomeSearchBar(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    final bool hasTyped = _homeSearchController.text.isNotEmpty;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isDark
            ? (widget.isIncognito
                  ? const Color(0xFF0D1B22)
                  : AppTheme.navySurface)
            : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _homeSearchFocus.hasFocus
              ? colors.primary
              : colors.primary.withValues(alpha: 0.42),
          width: _homeSearchFocus.hasFocus ? 1.6 : 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.primary.withValues(alpha: isDark ? 0.14 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          SearchEngineChipButton(
            currentEngine: widget.settings.searchEngine,
            onSelected: (engine) => widget.settings.setSearchEngine(engine),
          ),
          // Clickable Search Icon submits query (or focuses when empty)!
          IconButton(
            key: const Key('home_search_icon_button'),
            onPressed: _onSearchIconTap,
            icon: Icon(Icons.search_rounded, color: colors.primary, size: 21),
            tooltip: 'Search',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 38),
          ),
          Expanded(
            child: TextField(
              key: const Key('home_search_textfield'),
              controller: _homeSearchController,
              focusNode: _homeSearchFocus,
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: _onHomeSearchChanged,
              onSubmitted: _submitHomeSearch,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText:
                    'Search ${widget.settings.searchEngine.shortLabel} or type URL',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (hasTyped)
            IconButton(
              tooltip: 'Clear',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
              onPressed: () {
                _homeSearchController.clear();
                setState(() => _suggestions = <String>[]);
              },
              icon: const Icon(Icons.cancel_rounded, size: 18),
            )
          else
            IconButton(
              onPressed: widget.onVoiceSearch,
              icon: Icon(Icons.mic_rounded, color: colors.primary, size: 20),
              tooltip: 'Voice Search',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeSuggestionsCard(ColorScheme colors, bool isDark) {
    final List<String> recents = widget.isIncognito
        ? const <String>[]
        : widget.settings.matchingRecentSearches(
            _homeSearchController.text,
            limit: 6,
          );

    return Material(
      color: isDark ? AppTheme.navyElevated : Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (recents.isNotEmpty) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 2),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  title: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => widget.settings.removeRecentSearch(r),
                  ),
                  onTap: () => _submitHomeSearch(r),
                ),
              if (_suggestions.isNotEmpty) const Divider(height: 1),
            ],
            for (final String s in _suggestions)
              if (!recents.contains(s))
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _submitHomeSearch(s),
                ),
          ],
        ),
      ),
    );
  }

  /// Header with zero 'Reset Interests' button as requested!
  Widget _buildNewsSectionHeader(BuildContext context, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, size: 17, color: colors.primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Discover',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            if (_loadingNews)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final NewsCategoryTab tab in NewsCategoryTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Text(
                      tab.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: _selectedNewsTab == tab,
                    onSelected: (_) => _onSelectNewsCategory(tab),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyNewsState(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.newspaper_rounded,
              size: 36,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Pull down to load today\'s stories',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Google Discover-style Card:
  /// Edge-to-edge 16:9 top cover photo + publisher favicon + bold headline + time!
  Widget _buildGoogleDiscoverCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    PersonalizedNewsItem item,
  ) {
    final bool hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          unawaited(
            widget.interests.recordActivity(
              text: '${item.title} ${item.matchedTopic ?? ''}',
              weight: 2.0,
            ),
          );
          widget.onSelectUrl(item.url);
        },
        onLongPress: () => _showNewsMenu(context, item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasImage) _DiscoverCoverImage(imageUrl: item.imageUrl!),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.32,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        SiteLogo(
                          urlOrDomain: item.sourceUrl,
                          fallbackLabel: item.sourceName,
                          size: 18,
                          borderRadius: 5,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            item.timeLabel.isNotEmpty
                                ? '${item.sourceName} • ${item.timeLabel}'
                                : item.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (item.matchedTopic != null &&
                            item.matchedTopic!.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.matchedTopic!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showNewsMenu(context, item),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNewsMenu(
    BuildContext context,
    PersonalizedNewsItem item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(item.sourceName),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Open in New Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onOpenInNewTab(item.url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.shield_moon_outlined,
                  color: AppTheme.incognitoCyan,
                ),
                title: const Text('Open in Incognito Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onOpenInIncognitoTab(item.url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy Article Link'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: item.url));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIncognitoPrivacyNote(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.incognitoCyan.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.incognitoCyan.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: <Widget>[
          Icon(
            Icons.visibility_off_outlined,
            color: AppTheme.incognitoCyan,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'History, search queries, and personalized news signals are disabled in Incognito.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSiteMenu(BuildContext context, SiteUsageEntry site) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: SiteLogo(
                  urlOrDomain: site.url,
                  fallbackLabel: site.title,
                  size: 34,
                ),
                title: Text(
                  site.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  site.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Open in New Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onOpenInNewTab(site.url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.shield_moon_outlined,
                  color: AppTheme.incognitoCyan,
                ),
                title: const Text('Open in Incognito Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onOpenInIncognitoTab(site.url);
                },
              ),
              ListTile(
                leading: Icon(
                  site.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(site.isPinned ? 'Unpin Shortcut' : 'Pin Shortcut'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.settings.togglePinQuickSite(site.domain);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.fireCrimson,
                ),
                title: const Text(
                  'Remove from Home',
                  style: TextStyle(color: AppTheme.fireCrimson),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.settings.removeQuickLaunchSite(site.domain);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _QuickSiteTile extends StatelessWidget {
  const _QuickSiteTile({
    required this.site,
    required this.onTap,
    required this.onLongPress,
  });

  final SiteUsageEntry site;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.navySurface : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: SiteLogo(
                  urlOrDomain: site.url,
                  fallbackLabel: site.title,
                  size: 30,
                  borderRadius: 9,
                ),
              ),
              if (site.isPinned)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 9,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              site.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverCoverImage extends StatefulWidget {
  const _DiscoverCoverImage({required this.imageUrl});

  final String imageUrl;

  @override
  State<_DiscoverCoverImage> createState() => _DiscoverCoverImageState();
}

class _DiscoverCoverImageState extends State<_DiscoverCoverImage> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant _DiscoverCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          loadingBuilder:
              (
                BuildContext context,
                Widget child,
                ImageChunkEvent? loadingProgress,
              ) {
                if (loadingProgress == null) {
                  return child;
                }
                return Container(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                );
              },
          errorBuilder: (_, _, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_failed) {
                setState(() => _failed = true);
              }
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
