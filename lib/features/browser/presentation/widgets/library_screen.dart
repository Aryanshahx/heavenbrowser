import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/omnibox_parser.dart';
import '../../../../core/widgets/site_logo.dart';
import '../../../settings/browser_settings.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.settings,
    required this.onSelectUrl,
    required this.onOpenInNewTab,
    required this.onOpenInIncognitoTab,
    this.initialTabIndex = 0,
  });

  final BrowserSettingsController settings;
  final ValueChanged<String> onSelectUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final int initialTabIndex;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (BuildContext context, _) {
        final String lowerFilter = _filterQuery.trim().toLowerCase();

        final List<BookmarkItem> bookmarks = widget.settings.bookmarks.where((
          BookmarkItem b,
        ) {
          if (lowerFilter.isEmpty) return true;
          return b.title.toLowerCase().contains(lowerFilter) ||
              b.url.toLowerCase().contains(lowerFilter);
        }).toList();

        final List<HistoryItem> history = widget.settings.history.where((
          HistoryItem h,
        ) {
          if (lowerFilter.isEmpty) return true;
          return h.title.toLowerCase().contains(lowerFilter) ||
              h.url.toLowerCase().contains(lowerFilter);
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Library',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: <Widget>[
              if (_tabController.index == 1 &&
                  widget.settings.history.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClearHistory(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear'),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: <Widget>[
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.bookmarks_outlined, size: 17),
                        const SizedBox(width: 6),
                        Text('Bookmarks (${widget.settings.bookmarks.length})'),
                      ],
                    ),
                  ),
                ),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.history_rounded, size: 17),
                        const SizedBox(width: 6),
                        Text('History (${widget.settings.history.length})'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (String v) => setState(() => _filterQuery = v),
                    decoration: InputDecoration(
                      hintText: _tabController.index == 0
                          ? 'Search bookmarks...'
                          : 'Search history...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.42,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: <Widget>[
                      _buildBookmarksTab(context, colors, isDark, bookmarks),
                      _buildHistoryTab(context, colors, isDark, history),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookmarksTab(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    List<BookmarkItem> items,
  ) {
    if (items.isEmpty) {
      return _buildEmptyPlaceholder(
        colors,
        Icons.bookmark_border_rounded,
        'No bookmarks yet',
        'Open the browser menu on any webpage and tap Bookmark Page to save it here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final BookmarkItem item = items[index];
        return Dismissible(
          key: ValueKey<String>('bm_${item.url}_${item.createdAtMs}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => widget.settings.removeBookmark(item.url),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.fireCrimson,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
            ),
          ),
          child: _buildEntryCard(
            context: context,
            colors: colors,
            isDark: isDark,
            title: item.title,
            url: item.url,
            subtitle: OmniboxParser.cleanDomain(item.url),
            onDelete: () => widget.settings.removeBookmark(item.url),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    List<HistoryItem> items,
  ) {
    if (items.isEmpty) {
      return _buildEmptyPlaceholder(
        colors,
        Icons.history_rounded,
        'History is empty',
        'Websites visited in standard tabs appear here. Incognito tabs never record history.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final HistoryItem item = items[index];
        return Dismissible(
          key: ValueKey<String>('hist_${item.url}_${item.visitedAtMs}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => widget.settings.deleteHistoryItem(item),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.fireCrimson,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
            ),
          ),
          child: _buildEntryCard(
            context: context,
            colors: colors,
            isDark: isDark,
            title: item.title,
            url: item.url,
            subtitle:
                '${_formatRelativeTime(item.visitedAtMs)} • ${OmniboxParser.cleanDomain(item.url)}',
            onDelete: () => widget.settings.deleteHistoryItem(item),
          ),
        );
      },
    );
  }

  Widget _buildEntryCard({
    required BuildContext context,
    required ColorScheme colors,
    required bool isDark,
    required String title,
    required String url,
    required String subtitle,
    required VoidCallback onDelete,
  }) {
    return Material(
      color: isDark ? const Color(0xFF130B26) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.pop(context);
          widget.onSelectUrl(url);
        },
        onLongPress: () => _showEntryOptions(context, title, url, onDelete),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: <Widget>[
              SiteLogo(
                urlOrDomain: url,
                fallbackLabel: title,
                size: 38,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 19),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _showEntryOptions(context, title, url, onDelete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(
    ColorScheme colors,
    IconData icon,
    String title,
    String message,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 32, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
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

  Future<void> _showEntryOptions(
    BuildContext context,
    String title,
    String url,
    VoidCallback onDelete,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: SiteLogo(urlOrDomain: url, size: 34),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Open in New Tab'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.pop(context);
                  widget.onOpenInNewTab(url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.shield_moon_outlined,
                  color: AppTheme.incognitoCyan,
                ),
                title: const Text('Open in Incognito Tab'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.pop(context);
                  widget.onOpenInIncognitoTab(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy URL'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('URL copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.fireCrimson,
                ),
                title: const Text('Remove'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Clear Browsing History?'),
          content: const Text(
            'This removes all saved browsing history entries permanently.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await widget.settings.clearHistory();
    }
  }

  String _formatRelativeTime(int timestampMs) {
    if (timestampMs <= 0) return 'Recently';
    final Duration diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
