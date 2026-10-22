import 'package:flutter/material.dart';

import '../../../../core/widgets/site_logo.dart';
import '../../../settings/browser_settings.dart';

class LibrarySheet extends StatefulWidget {
  const LibrarySheet({
    super.key,
    required this.settings,
    required this.onSelectUrl,
    this.initialTabIndex = 0,
  });

  final BrowserSettingsController settings;
  final ValueChanged<String> onSelectUrl;
  final int initialTabIndex;

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet> {
  late int _tabIndex;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

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

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.80,
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: <ButtonSegment<int>>[
                            ButtonSegment<int>(
                              value: 0,
                              icon: const Icon(
                                Icons.bookmarks_rounded,
                                size: 17,
                              ),
                              label: Text(
                                'Bookmarks (${widget.settings.bookmarks.length})',
                              ),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              icon: const Icon(Icons.history_rounded, size: 17),
                              label: Text(
                                'History (${widget.settings.history.length})',
                              ),
                            ),
                          ],
                          selected: <int>{_tabIndex},
                          onSelectionChanged: (Set<int> val) {
                            setState(() => _tabIndex = val.first);
                          },
                        ),
                      ),
                      if (_tabIndex == 1 && widget.settings.history.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear all history',
                          icon: const Icon(Icons.delete_sweep_rounded),
                          onPressed: () => widget.settings.clearHistory(),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    onChanged: (String v) => setState(() => _filterQuery = v),
                    decoration: InputDecoration(
                      hintText: _tabIndex == 0
                          ? 'Filter bookmarks...'
                          : 'Search browsing history...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _tabIndex == 0
                      ? _buildBookmarksList(context, colors, bookmarks)
                      : _buildHistoryList(context, colors, history),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookmarksList(
    BuildContext context,
    ColorScheme colors,
    List<BookmarkItem> items,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bookmark_border_rounded,
              size: 46,
              color: colors.primary,
            ),
            const SizedBox(height: 10),
            const Text(
              'No saved bookmarks yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the star icon in the address bar on any site to save it.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
      itemBuilder: (BuildContext context, int index) {
        final BookmarkItem item = items[index];
        return ListTile(
          leading: SiteLogo(
            urlOrDomain: item.url,
            fallbackLabel: item.title,
            size: 38,
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            item.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: 'Remove bookmark',
            onPressed: () => widget.settings.removeBookmark(item.url),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onSelectUrl(item.url);
          },
        );
      },
    );
  }

  Widget _buildHistoryList(
    BuildContext context,
    ColorScheme colors,
    List<HistoryItem> items,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.history_rounded, size: 46, color: colors.primary),
            const SizedBox(height: 10),
            const Text(
              'Browsing history is clean',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Pages visited in Normal tabs appear here (Incognito never saves).',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
      itemBuilder: (BuildContext context, int index) {
        final HistoryItem item = items[index];
        return ListTile(
          leading: SiteLogo(
            urlOrDomain: item.url,
            fallbackLabel: item.title,
            size: 38,
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${_formatRelativeTime(item.visitedAtMs)} • ${item.url}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Remove entry',
            onPressed: () => widget.settings.deleteHistoryItem(item),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onSelectUrl(item.url);
          },
        );
      },
    );
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
