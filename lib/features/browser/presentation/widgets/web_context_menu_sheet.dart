import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shield/native_shield_bridge.dart';

/// Chrome / Brave-style long-press context menu for links, images, and linked
/// images inside any webpage.
class WebContextMenuSheet extends StatelessWidget {
  const WebContextMenuSheet({
    super.key,
    required this.data,
    required this.onOpenInNewTab,
    required this.onOpenInBackgroundTab,
    required this.onOpenInIncognitoTab,
    required this.onDownloadUrl,
  });

  final WebContextMenuData data;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInBackgroundTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final ValueChanged<String> onDownloadUrl;

  void _copyAndNotify(
    BuildContext context,
    ScaffoldMessengerState? messenger,
    String text,
    String toast,
  ) {
    Clipboard.setData(ClipboardData(text: text));
    Navigator.pop(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(toast),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );

    final String headerTitle = data.linkText.isNotEmpty
        ? data.linkText
        : (data.imageAlt.isNotEmpty
              ? data.imageAlt
              : (data.hasLink ? 'Link Options' : 'Image Options'));
    final String headerSub = data.hasLink ? data.linkUrl : data.imageUrl;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: SingleChildScrollView(
          key: const Key('web_context_menu_sheet'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                margin: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.navySurface
                      : colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    if (data.hasImage &&
                        (data.imageUrl.startsWith('http://') ||
                            data.imageUrl.startsWith('https://')))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            data.imageUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 48,
                              height: 48,
                              color: colors.primary.withValues(alpha: 0.14),
                              child: Icon(
                                Icons.image_outlined,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          data.hasImage
                              ? Icons.image_outlined
                              : Icons.link_rounded,
                          color: colors.primary,
                          size: 21,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            headerTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            headerSub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (data.hasLink) ...<Widget>[
                if (data.hasImage)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                    child: Text(
                      'LINK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                _ContextTile(
                  tileKey: const Key('ctx_open_new_tab'),
                  icon: Icons.open_in_new_rounded,
                  title: 'Open in new tab',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenInNewTab(data.linkUrl);
                  },
                ),
                _ContextTile(
                  tileKey: const Key('ctx_open_bg_tab'),
                  icon: Icons.tab_unselected_rounded,
                  title: 'Open in background tab',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenInBackgroundTab(data.linkUrl);
                  },
                ),
                _ContextTile(
                  tileKey: const Key('ctx_open_incognito_tab'),
                  icon: Icons.shield_moon_outlined,
                  title: 'Open in Incognito tab',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenInIncognitoTab(data.linkUrl);
                  },
                ),
                _ContextTile(
                  tileKey: const Key('ctx_copy_link'),
                  icon: Icons.copy_rounded,
                  title: 'Copy link address',
                  onTap: () => _copyAndNotify(
                    context,
                    messenger,
                    data.linkUrl,
                    'Link copied to clipboard',
                  ),
                ),
                if (data.linkText.isNotEmpty)
                  _ContextTile(
                    tileKey: const Key('ctx_copy_link_text'),
                    icon: Icons.short_text_rounded,
                    title: 'Copy link text',
                    onTap: () => _copyAndNotify(
                      context,
                      messenger,
                      data.linkText,
                      'Link text copied',
                    ),
                  ),
                if (data.linkUrl.startsWith('http://') ||
                    data.linkUrl.startsWith('https://'))
                  _ContextTile(
                    tileKey: const Key('ctx_download_link'),
                    icon: Icons.download_rounded,
                    title: 'Download link',
                    onTap: () {
                      Navigator.pop(context);
                      onDownloadUrl(data.linkUrl);
                    },
                  ),
                _ContextTile(
                  tileKey: const Key('ctx_share_link'),
                  icon: Icons.share_outlined,
                  title: 'Share link',
                  onTap: () {
                    Navigator.pop(context);
                    SharePlus.instance.share(
                      ShareParams(
                        text: data.linkUrl,
                        subject: data.linkText.isNotEmpty
                            ? data.linkText
                            : null,
                      ),
                    );
                  },
                ),
              ],

              if (data.hasLink && data.hasImage)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(height: 1),
                ),

              if (data.hasImage) ...<Widget>[
                if (data.hasLink)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Text(
                      'IMAGE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                _ContextTile(
                  tileKey: const Key('ctx_open_image_new_tab'),
                  icon: Icons.image_search_rounded,
                  title: 'Open image in new tab',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenInNewTab(data.imageUrl);
                  },
                ),
                _ContextTile(
                  tileKey: const Key('ctx_download_image'),
                  icon: Icons.file_download_outlined,
                  title: 'Download image',
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadUrl(data.imageUrl);
                  },
                ),
                if (data.imageUrl.startsWith('http://') ||
                    data.imageUrl.startsWith('https://'))
                  _ContextTile(
                    tileKey: const Key('ctx_search_image_google'),
                    icon: Icons.manage_search_rounded,
                    title: 'Search image with Google',
                    onTap: () {
                      Navigator.pop(context);
                      final String lensUrl =
                          'https://lens.google.com/uploadbyurl?url=${Uri.encodeQueryComponent(data.imageUrl)}';
                      onOpenInNewTab(lensUrl);
                    },
                  ),
                _ContextTile(
                  tileKey: const Key('ctx_copy_image_url'),
                  icon: Icons.link_rounded,
                  title: 'Copy image link',
                  onTap: () => _copyAndNotify(
                    context,
                    messenger,
                    data.imageUrl,
                    'Image link copied',
                  ),
                ),
                _ContextTile(
                  tileKey: const Key('ctx_share_image'),
                  icon: Icons.share_rounded,
                  title: 'Share image',
                  onTap: () {
                    Navigator.pop(context);
                    SharePlus.instance.share(ShareParams(text: data.imageUrl));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextTile extends StatelessWidget {
  const _ContextTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: tileKey,
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, size: 20),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        onTap: onTap,
      ),
    );
  }
}
