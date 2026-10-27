import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/omnibox_parser.dart';
import '../../../../core/widgets/site_logo.dart';
import '../../../shield/native_shield_bridge.dart';
import '../../engine/browser_engine.dart';

class OfflinePageItem {
  const OfflinePageItem({
    required this.id,
    required this.title,
    required this.url,
    required this.filePath,
    required this.sizeBytes,
    required this.savedAtMs,
  });

  factory OfflinePageItem.fromJson(Map<String, Object?> json) {
    return OfflinePageItem(
      id: (json['id']?.toString() ?? '').trim(),
      title: (json['title']?.toString() ?? 'Saved Page').trim(),
      url: (json['url']?.toString() ?? '').trim(),
      filePath: (json['filePath']?.toString() ?? '').trim(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String url;
  final String filePath;
  final int sizeBytes;
  final int savedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'url': url,
    'filePath': filePath,
    'sizeBytes': sizeBytes,
    'savedAtMs': savedAtMs,
  };
}

class OfflinePagesController extends ChangeNotifier {
  OfflinePagesController(this._prefs) {
    _load();
  }

  static const String _storageKey = 'heaven_offline_pages_v1';
  final SharedPreferences _prefs;
  List<OfflinePageItem> _items = <OfflinePageItem>[];

  List<OfflinePageItem> get items => List<OfflinePageItem>.unmodifiable(_items);

  void _load() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        _items = decoded
            .whereType<Map<String, Object?>>()
            .map(OfflinePageItem.fromJson)
            .where((OfflinePageItem e) => e.id.isNotEmpty)
            .toList();
      }
    } on FormatException {
      _items = <OfflinePageItem>[];
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(_items.map((OfflinePageItem e) => e.toJson()).toList()),
    );
  }

  Future<OfflinePageItem?> saveCurrentPage(BrowserEngine engine) async {
    if (!engine.isShowingWebPage) return null;
    final String url = engine.currentUrl ?? '';
    final String title = engine.pageTitle;
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .saveOfflinePage(
          webViewId: engine.androidWebViewId,
          title: title,
          url: url,
        );

    OfflinePageItem saved;
    if (res['ok'] == true &&
        (res['filePath']?.toString().isNotEmpty ?? false)) {
      saved = OfflinePageItem(
        id: res['id']?.toString() ??
            'offline_${DateTime.now().millisecondsSinceEpoch}',
        title: res['title']?.toString() ?? title,
        url: res['url']?.toString() ?? url,
        filePath: res['filePath']!.toString(),
        sizeBytes: (res['sizeBytes'] as num?)?.toInt() ?? 0,
        savedAtMs:
            (res['savedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
    } else if (!engine.enablePlatformWebView) {
      // Headless widget-test mode snapshot entry
      final int now = DateTime.now().millisecondsSinceEpoch;
      saved = OfflinePageItem(
        id: 'offline_$now',
        title: title,
        url: url,
        filePath: '/offline_pages/offline_$now.mht',
        sizeBytes: 24576,
        savedAtMs: now,
      );
    } else {
      return null;
    }

    _items = <OfflinePageItem>[
      saved,
      ..._items.where((OfflinePageItem e) => e.url != saved.url),
    ];
    await _persist();
    notifyListeners();
    return saved;
  }

  Future<void> removePage(OfflinePageItem item) async {
    if (item.filePath.isNotEmpty) {
      await NativeShieldBridge.instance.deleteOfflinePage(
        filePath: item.filePath,
      );
    }
    _items = _items.where((OfflinePageItem e) => e.id != item.id).toList();
    await _persist();
    notifyListeners();
  }
}

class OfflinePagesSheet extends StatefulWidget {
  const OfflinePagesSheet({
    super.key,
    required this.engine,
    required this.controller,
  });

  final BrowserEngine engine;
  final OfflinePagesController controller;

  @override
  State<OfflinePagesSheet> createState() => _OfflinePagesSheetState();
}

class _OfflinePagesSheetState extends State<OfflinePagesSheet> {
  bool _savingOffline = false;

  static String _formatSize(int bytes) {
    if (bytes <= 0) return 'Saved';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleSaveOffline() async {
    if (_savingOffline || !widget.engine.isShowingWebPage) return;
    setState(() => _savingOffline = true);
    final OfflinePageItem? item = await widget.controller.saveCurrentPage(
      widget.engine,
    );
    if (!mounted) return;
    setState(() => _savingOffline = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item != null
              ? 'Saved "${item.title}" for offline reading'
              : 'Wait for page to finish loading before saving offline',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSavePdf() async {
    if (!widget.engine.isShowingWebPage) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    Navigator.pop(context);
    final bool ok = await NativeShieldBridge.instance.saveWebPageAsPdf(
      webViewId: widget.engine.androidWebViewId,
      title: widget.engine.pageTitle,
    );
    if (!ok && widget.engine.enablePlatformWebView) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Could not open PDF exporter for this page'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool hasWebPage = widget.engine.isShowingWebPage;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, _) {
        final List<OfflinePageItem> pages = widget.controller.items;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: Padding(
              key: const Key('offline_pages_sheet'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.offline_pin_rounded,
                        color: colors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Offline Pages & Save as PDF',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('save_offline_page_button'),
                          onPressed: hasWebPage && !_savingOffline
                              ? _handleSaveOffline
                              : null,
                          icon: _savingOffline
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download_for_offline_outlined),
                          label: const Text('Save Offline'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('save_webpage_pdf_button'),
                          onPressed: hasWebPage ? _handleSavePdf : null,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Save as PDF'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Saved Offline Pages (${pages.length})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (pages.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.navySurface
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.45,
                              ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        hasWebPage
                            ? 'Tap "Save Offline" above to keep a full copy of this webpage for reading without internet, or "Save as PDF" to export a PDF.'
                            : 'Open any webpage to save it offline or export it as a PDF. Your saved offline pages will appear here.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: pages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (BuildContext context, int i) {
                          final OfflinePageItem item = pages[i];
                          return Material(
                            color: isDark
                                ? AppTheme.navySurface
                                : colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              key: Key('offline_page_item_${item.id}'),
                              dense: true,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: SiteLogo(
                                urlOrDomain: item.url,
                                fallbackLabel: item.title,
                                size: 30,
                                borderRadius: 8,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Text(
                                '${OmniboxParser.cleanDomain(item.url)} • ${_formatSize(item.sizeBytes)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: IconButton(
                                key: Key('delete_offline_page_${item.id}'),
                                tooltip: 'Delete Offline Copy',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 19,
                                ),
                                onPressed: () =>
                                    widget.controller.removePage(item),
                              ),
                              onTap: () async {
                                Navigator.pop(context);
                                await widget.engine.loadSavedOfflineArchive(
                                  filePath: item.filePath,
                                  title: item.title,
                                  originalUrl: item.url,
                                );
                              },
                            ),
                          );
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
