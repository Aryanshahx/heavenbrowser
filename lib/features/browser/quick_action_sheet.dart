import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../downloads/downloads_controller.dart';
import '../downloads/media_grabber_sheet.dart';
import '../extensions/extensions_controller.dart';
import '../settings/browser_settings.dart';
import '../shield/native_shield_bridge.dart';
import 'engine/browser_engine.dart';
import 'site_controls_sheet.dart';

class QuickActionSheet extends StatefulWidget {
  const QuickActionSheet({
    super.key,
    required this.engine,
    required this.settings,
    required this.downloads,
    required this.extensions,
    required this.onOpenExtensions,
  });

  final BrowserEngine engine;
  final BrowserSettingsController settings;
  final DownloadsController downloads;
  final ExtensionsController extensions;
  final VoidCallback onOpenExtensions;

  static Future<void> show(
    BuildContext context, {
    required BrowserEngine engine,
    required BrowserSettingsController settings,
    required DownloadsController downloads,
    required ExtensionsController extensions,
    required VoidCallback onOpenExtensions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickActionSheet(
        engine: engine,
        settings: settings,
        downloads: downloads,
        extensions: extensions,
        onOpenExtensions: onOpenExtensions,
      ),
    );
  }

  @override
  State<QuickActionSheet> createState() => _QuickActionSheetState();
}

class _QuickActionSheetState extends State<QuickActionSheet> {
  bool _customizing = false;

  IconData _iconFor(QuickActionItem item) {
    return switch (item) {
      QuickActionItem.refresh => Icons.refresh_rounded,
      QuickActionItem.bookmark =>
        widget.settings.isBookmarked(widget.engine.currentUrl)
            ? Icons.bookmark_rounded
            : Icons.bookmark_border_rounded,
      QuickActionItem.media => Icons.video_collection_rounded,
      QuickActionItem.pip => Icons.picture_in_picture_alt_rounded,
      QuickActionItem.dataSaver => Icons.data_saver_on_rounded,
      QuickActionItem.desktop => Icons.desktop_windows_rounded,
      QuickActionItem.permissions => Icons.admin_panel_settings_rounded,
      QuickActionItem.extensions => Icons.extension_rounded,
    };
  }

  bool _isActive(QuickActionItem item) {
    return switch (item) {
      QuickActionItem.bookmark => widget.settings.isBookmarked(
        widget.engine.currentUrl,
      ),
      QuickActionItem.dataSaver => widget.settings.ultraDataSaverMode,
      QuickActionItem.desktop => widget.settings.desktopMode,
      QuickActionItem.media => widget.engine.detectedMediaStreams.isNotEmpty,
      QuickActionItem.extensions => widget.extensions.enabledCount > 0,
      _ => false,
    };
  }

  Future<void> _trigger(BuildContext context, QuickActionItem item) async {
    switch (item) {
      case QuickActionItem.refresh:
        Navigator.pop(context);
        await widget.engine.reloadOrStop();
      case QuickActionItem.bookmark:
        final String? url = widget.engine.currentUrl;
        if (url != null && url.isNotEmpty) {
          final bool added = await widget.settings.toggleBookmark(
            url: url,
            title: widget.engine.pageTitle,
          );
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(added ? 'Bookmarked page!' : 'Removed bookmark'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case QuickActionItem.media:
        Navigator.pop(context);
        await MediaGrabberSheet.show(
          context,
          engine: widget.engine,
          downloads: widget.downloads,
          settings: widget.settings,
        );
      case QuickActionItem.pip:
        Navigator.pop(context);
        await NativeShieldBridge.instance.enterPictureInPicture();
      case QuickActionItem.dataSaver:
        final bool next = !widget.settings.ultraDataSaverMode;
        await widget.settings.setUltraDataSaverMode(next);
        if (!widget.engine.isShowingStartPage) {
          await widget.engine.reloadFullPage();
        }
      case QuickActionItem.desktop:
        Navigator.pop(context);
        await widget.engine.setDesktopModeAndReload(
          !widget.settings.desktopMode,
        );
      case QuickActionItem.permissions:
        Navigator.pop(context);
        await SiteControlsSheet.show(
          context,
          engine: widget.engine,
          settings: widget.settings,
        );
      case QuickActionItem.extensions:
        Navigator.pop(context);
        widget.onOpenExtensions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          widget.engine,
          widget.settings,
          widget.extensions,
        ]),
        builder: (BuildContext context, _) {
          final List<QuickActionItem> activeItems =
              widget.settings.quickActionItems;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.flash_on_rounded, color: colors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'One-Handed Quick Actions',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('customize_quick_actions_button'),
                      onPressed: () =>
                          setState(() => _customizing = !_customizing),
                      icon: Icon(
                        _customizing ? Icons.check_rounded : Icons.tune_rounded,
                        size: 16,
                      ),
                      label: Text(_customizing ? 'Done' : 'Customize'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_customizing) ...<Widget>[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Left-Handed Corner Placement',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Move floating Quick Action button to bottom-left corner',
                    ),
                    value: widget.settings.quickActionLeftHanded,
                    onChanged: widget.settings.setQuickActionLeftHanded,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final QuickActionItem candidate
                          in QuickActionItem.values)
                        FilterChip(
                          selected: activeItems.contains(candidate),
                          onSelected: (_) =>
                              widget.settings.toggleQuickActionItem(candidate),
                          avatar: Icon(_iconFor(candidate), size: 16),
                          label: Text(candidate.label),
                        ),
                    ],
                  ),
                ] else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activeItems.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.05,
                        ),
                    itemBuilder: (BuildContext context, int index) {
                      final QuickActionItem item = activeItems[index];
                      final bool highlighted = _isActive(item);
                      return Material(
                        color: highlighted
                            ? colors.primary.withValues(alpha: 0.18)
                            : (isDark
                                  ? AppTheme.navySurface
                                  : colors.surfaceContainerHighest.withValues(
                                      alpha: 0.45,
                                    )),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: Key('quick_action_${item.name}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _trigger(context, item),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  _iconFor(item),
                                  size: 22,
                                  color: highlighted
                                      ? colors.primary
                                      : colors.onSurface,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: highlighted
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: highlighted
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
