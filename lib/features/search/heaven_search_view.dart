import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../../core/widgets/site_logo.dart';
import 'heaven_search_service.dart';

class HeavenSearchView extends StatefulWidget {
  const HeavenSearchView({
    super.key,
    required this.query,
    required this.searchService,
    required this.onOpenUrl,
    required this.onOpenInNewTab,
    required this.onOpenInIncognitoTab,
    required this.onSubmitNewQuery,
    this.isIncognito = false,
  });

  final String query;
  final HeavenSearchService searchService;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final ValueChanged<String> onSubmitNewQuery;
  final bool isIncognito;

  @override
  State<HeavenSearchView> createState() => _HeavenSearchViewState();
}

class _HeavenSearchViewState extends State<HeavenSearchView> {
  HeavenSearchTab _selectedTab = HeavenSearchTab.web;
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
      _future = widget.searchService.search(widget.query);
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
                child: Text(
                  'Enter a query above to search privately with Heaven Search.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
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
                              Text('Searching the private web...'),
                            ],
                          ),
                        ),
                      );
                    }

                    final HeavenSearchResponse? data = snapshot.data;
                    if (data == null) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildErrorOrEmptyState(context, colors),
                      );
                    }

                    final List<HeavenSearchResult> activeResults =
                        switch (_selectedTab) {
                          HeavenSearchTab.web => data.webResults,
                          HeavenSearchTab.knowledge => data.knowledgeResults,
                          HeavenSearchTab.tech => data.techResults,
                        };

                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
                      sliver: SliverList.list(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, left: 4),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.verified_user_rounded,
                                  size: 14,
                                  color: widget.isIncognito
                                      ? AppTheme.incognitoOrchid
                                      : AppTheme.shieldEmerald,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${activeResults.length} private results in '
                                    '${(data.elapsedMs / 1000).toStringAsFixed(2)}s '
                                    '• Zero tracking cookies',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (data.instantMathResult != null &&
                              _selectedTab == HeavenSearchTab.web)
                            _buildCalculatorCard(
                              context,
                              colors,
                              data.query,
                              data.instantMathResult!,
                            ),
                          if (data.knowledgeCard != null &&
                              _selectedTab != HeavenSearchTab.tech)
                            _buildKnowledgePanel(
                              context,
                              colors,
                              data.knowledgeCard!,
                            ),
                          if (activeResults.isEmpty)
                            _buildErrorOrEmptyState(context, colors)
                          else
                            for (final HeavenSearchResult item in activeResults)
                              _buildResultCard(context, colors, isDark, item),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  AppConstants.logoAssetPath,
                  width: 30,
                  height: 30,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.bolt_rounded, color: AppTheme.neonCyan),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Heaven Search',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (widget.isIncognito
                              ? AppTheme.incognitoOrchid
                              : AppTheme.neonCyan)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.isIncognito ? 'STEALTH' : 'PRIVATE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: widget.isIncognito
                        ? AppTheme.incognitoOrchid
                        : colors.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _runSearch,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh results',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF111A2E)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (String value) {
                if (value.trim().isNotEmpty) {
                  widget.onSubmitNewQuery(value.trim());
                }
              },
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: 'Search privately with Heaven...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  tooltip: 'Search',
                  onPressed: () {
                    final String val = _searchController.text.trim();
                    if (val.isNotEmpty) {
                      widget.onSubmitNewQuery(val);
                    }
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final HeavenSearchTab tab in HeavenSearchTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tab.label),
                      selected: _selectedTab == tab,
                      onSelected: (_) => setState(() => _selectedTab = tab),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(16),
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
                size: 28,
                borderRadius: 8,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.heading,
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
                    width: 74,
                    height: 74,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onOpenUrl(card.sourceUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Read Full Source'),
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
        color: isDark ? const Color(0xFF0E1628) : Colors.white,
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
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SiteLogo(
                    urlOrDomain: item.url,
                    fallbackLabel: item.displayDomain,
                    size: 28,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
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
                          item.url,
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
                  if (item.metaBadge != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.metaBadge!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Result options',
                    onPressed: () => _showResultMenu(context, item),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF7DD3FC)
                      : const Color(0xFF1D4ED8),
                  height: 1.28,
                ),
              ),
              if (item.snippet.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
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

  Widget _buildErrorOrEmptyState(BuildContext context, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.travel_explore_rounded, size: 46, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            'No direct results found for "${widget.query}"',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your connection or try opening the query on an external search index below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
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
            'Compare query on external engines:',
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
                  color: AppTheme.incognitoOrchid,
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
