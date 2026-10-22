import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/features/browser/engine/browser_engine.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';

class SitePrivacySheet extends StatelessWidget {
  const SitePrivacySheet({
    super.key,
    required this.pageState,
    required this.settings,
    required this.onToggleSiteTrust,
    required this.onClearSiteData,
  });

  final BrowserPageState pageState;
  final BrowserSettingsController settings;
  final VoidCallback onToggleSiteTrust;
  final VoidCallback onClearSiteData;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String url = pageState.currentUrl ?? '';
    final String host = pageState.host ?? url;
    final bool isTrusted = settings.isHostTrusted(host);
    final bool shieldActiveOnSite = settings.shieldEnabled && !isTrusted;
    final Map<String, int> domainCounts = <String, int>{};
    for (final String d in pageState.blockedDomainsOnPage) {
      domainCounts[d] = (domainCounts[d] ?? 0) + 1;
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  pageState.isSecureHttps
                      ? Icons.lock_rounded
                      : Icons.warning_amber_rounded,
                  color: pageState.isSecureHttps
                      ? AppTheme.shieldEmerald
                      : AppTheme.warningAmber,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Full URL',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('URL copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              pageState.isSecureHttps
                  ? 'Encrypted HTTPS connection'
                  : 'Unencrypted HTTP connection',
              style: textTheme.bodySmall?.copyWith(
                color: pageState.isSecureHttps
                    ? AppTheme.shieldEmerald
                    : AppTheme.warningAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Heaven Shield on this site'),
              subtitle: Text(
                shieldActiveOnSite
                    ? 'Blocking trackers, ads & fingerprinting'
                    : 'Paused for $host',
              ),
              value: shieldActiveOnSite,
              onChanged: settings.shieldEnabled
                  ? (_) {
                      Navigator.of(context).pop();
                      onToggleSiteTrust();
                    }
                  : null,
            ),
            const Divider(height: 24),
            Text(
              'Blocked on this page (${pageState.blockedDomainsOnPage.length})',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (domainCounts.isEmpty)
              Text(
                'No tracker requests intercepted on this page yet.',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              ...domainCounts.entries.map(
                (MapEntry<String, int> entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.block_rounded,
                        size: 16,
                        color: AppTheme.shieldEmerald,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        '×${entry.value}',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onClearSiteData();
                },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Clear Cookies & Site Storage'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
