import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../../core/widgets/site_logo.dart';
import '../downloads/downloads_controller.dart';
import 'heaven_search_service.dart';

class HeavenSearchView extends StatefulWidget {
  const HeavenSearchView({
    super.key,
    required this.query,
    required this.searchService,
    required this.downloads,
    required this.onOpenUrl,
    required this.onOpenInNewTab,
    required this.onOpenInIncognitoTab,
    required this.onSubmitNewQuery,
    required this.onVoiceSearch,
    this.isIncognito = false,
  });

  final String query;
  final HeavenSearchService searchService;
  final DownloadsController downloads;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final ValueChanged<String> onSubmitNewQuery;
  final VoidCallback onVoiceSearch;
  final bool isIncognito;

  @override
  State<HeavenSearchView> createState() => _HeavenSearchViewState();
}

class _HeavenSearchViewState extends State<HeavenSearchView> {
  HeavenSearchTab _selectedTab = HeavenSearchTab.all;
  HeavenSearchFilters _filters = const HeavenSearchFilters();
  Future<HeavenSearchResponse>? _future;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
    _runSearch();
  }

  @override
  void didUpdateWidget(covariant HeavenSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _searchController.text = widget.query;
      _runSearch();
    }
  }

  void _runSearch() {
    if (widget.query.trim().isEmpty) {
      _future = null;
      return;
    }
    setState(() {
      _future = widget.searchService.search(widget.query, filters: _filters);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        _runSearch();
        final Future<HeavenSearchResponse>? f = _future;
        if (f != null) {
          await f;
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _buildSearchHeader(context, colors, isDark),
          ),
          if (_future == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Type or speak a query above to search privately.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            FutureBuilder<HeavenSearchResponse>(
              future: _future,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<HeavenSearchResponse> snapshot,
                  ) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircularProgressIndicator(),
                              SizedBox(height: 14),
                              Text('Searching privately...'),
                            ],
                          ),
                        ),
                      );
                    }

                    final HeavenSearchResponse? data = snapshot.data;
                    if (data == null) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context, colors),
                      );
                    }

                    if (_selectedTab == HeavenSearchTab.images) {
                      return _buildImagesSliver(
                        context,
                        colors,
                        data.imageResults,
                      );
                    }

                    final List<HeavenSearchResult> activeResults =
                        switch (_selectedTab) {
                          HeavenSearchTab.all => data.webResults,
                          HeavenSearchTab.videos => data.videoResults,
                          HeavenSearchTab.news => data.newsResults,
                          HeavenSearchTab.wiki => data.wikiResults,
                          HeavenSearchTab.images =>
                            const <HeavenSearchResult>[],
                        };

                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                      sliver: SliverList.list(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, left: 4),
                            child: Text(
                              '${activeResults.length} results (${(data.elapsedMs / 1000).toStringAsFixed(2)}s) • ${_filters.region.label}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (data.instantMathResult != null &&
                              _selectedTab == HeavenSearchTab.all)
                            _buildCalculatorCard(
                              context,
                              colors,
                              data.query,
                              data.instantMathResult!,
                            ),
                          if (data.knowledgeCard != null &&
                              _selectedTab == HeavenSearchTab.all)
                            _buildKnowledgePanel(
                              context,
                              colors,
                              data.knowledgeCard!,
                            ),
                          if (activeResults.isEmpty)
                            _buildEmptyState(context, colors)
                          else
                            for (final HeavenSearchResult item in activeResults)
                              _selectedTab == HeavenSearchTab.videos
                                  ? _buildVideoCard(
                                      context,
                                      colors,
                                      isDark,
                                      item,
                                    )
                                  : _buildResultCard(
                                      context,
                                      colors,
                                      isDark,
                                      item,
                                    ),
                          const SizedBox(height: 12),
                          _buildExternalFallbackBar(context, colors),
                        ],
                      ),
                    );
                  },
            ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.navyElevated
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.primary.withValues(alpha: 0.38)),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 12),
                Icon(Icons.search_rounded, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (String value) {
                      if (value.trim().isNotEmpty) {
                        widget.onSubmitNewQuery(value.trim());
                      }
                    },
                    style: const TextStyle(fontSize: 14.5),
                    decoration: const InputDecoration(
                      hintText: 'Search Heaven...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.mic_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Voice Search',
                  onPressed: widget.onVoiceSearch,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Search',
                  onPressed: () {
                    final String val = _searchController.text.trim();
                    if (val.isNotEmpty) {
                      widget.onSubmitNewQuery(val);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Vertical category tabs (all 5 fit cleanly in full view on any phone width)
          Row(
            children: <Widget>[
              for (final HeavenSearchTab tab in HeavenSearchTab.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => setState(() => _selectedTab = tab),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          vertical: 7,
                          horizontal: 4,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _selectedTab == tab
                              ? colors.primary
                              : colors.surfaceContainerHighest.withValues(
                                  alpha: 0.45,
                                ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: _selectedTab == tab
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Working search filters row (Time, Region, SafeSearch)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _FilterPillButton(
                  icon: Icons.schedule_rounded,
                  label: _filters.time.label,
                  active: _filters.time != HeavenTimeFilter.any,
                  onTap: () => _pickTimeFilter(context),
                ),
                const SizedBox(width: 6),
                _FilterPillButton(
                  icon: Icons.public_rounded,
                  label: _filters.region.label,
                  active: false,
                  onTap: () => _pickRegionFilter(context),
                ),
                const SizedBox(width: 6),
                _FilterPillButton(
                  icon: Icons.verified_user_outlined,
                  label: _filters.safe.label,
                  active: _filters.safe != HeavenSafeFilter.off,
                  onTap: () => _pickSafeFilter(context),
                ),
                if (_filters.hasActiveCustomFilter) ...<Widget>[
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      setState(() {
                        _filters = HeavenSearchFilters(region: _filters.region);
                      });
                      _runSearch();
                    },
                    child: const Text('Reset', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  SliverPadding _buildImagesSliver(
    BuildContext context,
    ColorScheme colors,
    List<HeavenImageResult> images,
  ) {
    if (images.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverToBoxAdapter(child: _buildEmptyState(context, colors)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 195,
        ),
        itemCount: images.length,
        itemBuilder: (BuildContext context, int index) {
          final HeavenImageResult img = images[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showImagePreviewDialog(context, img),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Image.network(
                      img.thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 32),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      img.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    HeavenSearchResult item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenUrl(item.url),
        onLongPress: () => _showResultMenu(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (item.thumbnailUrl != null)
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.black26,
                        child: const Icon(
                          Icons.play_circle_outline_rounded,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      SiteLogo(
                        urlOrDomain: item.url,
                        size: 20,
                        borderRadius: 6,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.displayDomain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
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
    );
  }

  Widget _buildCalculatorCard(
    BuildContext context,
    ColorScheme colors,
    String expression,
    String answer,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            colors.primary.withValues(alpha: 0.16),
            colors.secondary.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.calculate_rounded, color: colors.primary, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$expression =',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  answer,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy result',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: answer));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $answer'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKnowledgePanel(
    BuildContext context,
    ColorScheme colors,
    HeavenKnowledgeCard card,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SiteLogo(
                urlOrDomain: card.sourceUrl,
                fallbackLabel: card.sourceName,
                size: 26,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.sourceName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  card.summary,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.42),
                ),
              ),
              if (card.imageUrl != null) ...<Widget>[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    card.imageUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onOpenUrl(card.sourceUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Read Full Article'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    HeavenSearchResult item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.onOpenUrl(item.url),
        onLongPress: () => _showResultMenu(context, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SiteLogo(
                    urlOrDomain: item.url,
                    fallbackLabel: item.sourceLabel,
                    size: 26,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.metaBadge ??
                              OmniboxParser.friendlySiteTitleFromDomain(
                                item.displayDomain,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          item.displayDomain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Options',
                    onPressed: () => _showResultMenu(context, item),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.skyHighlight : AppTheme.sapphireBlue,
                  height: 1.3,
                ),
              ),
              if (item.snippet.isNotEmpty) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  item.snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.travel_explore_rounded, size: 44, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            'No results for "${widget.query}" with current filter',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 14),
          _buildExternalFallbackBar(context, colors),
        ],
      ),
    );
  }

  Widget _buildExternalFallbackBar(BuildContext context, ColorScheme colors) {
    final List<SearchEngine> externals = <SearchEngine>[
      SearchEngine.duckDuckGo,
      SearchEngine.brave,
      SearchEngine.startpage,
      SearchEngine.google,
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Try this query on other engines:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final SearchEngine engine in externals)
                ActionChip(
                  avatar: SiteLogo(
                    urlOrDomain: engine.homeUrl,
                    size: 18,
                    borderRadius: 5,
                  ),
                  label: Text(engine.shortLabel),
                  onPressed: () =>
                      widget.onOpenUrl(engine.buildSearchUrl(widget.query)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTimeFilter(BuildContext context) async {
    final HeavenTimeFilter? picked =
        await showModalBottomSheet<HeavenTimeFilter>(
          context: context,
          builder: (BuildContext ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Filter by Time',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  for (final HeavenTimeFilter f in HeavenTimeFilter.values)
                    ListTile(
                      leading: Icon(
                        _filters.time == f
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                      ),
                      title: Text(f.label),
                      onTap: () => Navigator.pop(ctx, f),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
    if (picked != null && picked != _filters.time) {
      setState(() => _filters = _filters.copyWith(time: picked));
      _runSearch();
    }
  }

  Future<void> _pickRegionFilter(BuildContext context) async {
    final HeavenRegionFilter? picked =
        await showModalBottomSheet<HeavenRegionFilter>(
          context: context,
          builder: (BuildContext ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Search Region',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  for (final HeavenRegionFilter r in HeavenRegionFilter.values)
                    ListTile(
                      leading: Icon(
                        _filters.region == r
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                      ),
                      title: Text(r.label),
                      onTap: () => Navigator.pop(ctx, r),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
    if (picked != null && picked != _filters.region) {
      setState(() => _filters = _filters.copyWith(region: picked));
      _runSearch();
    }
  }

  Future<void> _pickSafeFilter(BuildContext context) async {
    final HeavenSafeFilter? picked =
        await showModalBottomSheet<HeavenSafeFilter>(
          context: context,
          builder: (BuildContext ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'SafeSearch Filter',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  for (final HeavenSafeFilter s in HeavenSafeFilter.values)
                    ListTile(
                      leading: Icon(
                        _filters.safe == s
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                      ),
                      title: Text(s.label),
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
    if (picked != null && picked != _filters.safe) {
      setState(() => _filters = _filters.copyWith(safe: picked));
      _runSearch();
    }
  }

  Future<void> _showImagePreviewDialog(
    BuildContext context,
    HeavenImageResult img,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: Image.network(
                  img.thumbUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 160,
                    child: Icon(Icons.broken_image_outlined, size: 42),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      img.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            widget.onOpenUrl(img.pageUrl);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Source Page'),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await widget.downloads.startUrlDownload(
                              url: img.fullUrl,
                            );
                          },
                          icon: const Icon(Icons.download_rounded, size: 17),
                          label: const Text('Download'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showResultMenu(
    BuildContext context,
    HeavenSearchResult item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: SiteLogo(urlOrDomain: item.url, size: 34),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.url,
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
                title: const Text('Copy Link'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: item.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share Link'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  SharePlus.instance.share(
                    ShareParams(text: item.url, subject: item.title),
                  );
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

class _FilterPillButton extends StatelessWidget {
  const _FilterPillButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.18)
              : colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 13.5,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? colors.primary : colors.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 15,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
