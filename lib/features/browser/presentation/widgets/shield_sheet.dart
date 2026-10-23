import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/site_logo.dart';
import '../../../settings/browser_settings.dart';
import '../../../vpn/vpn_controller.dart';
import '../../engine/browser_engine.dart';

class ShieldSheet extends StatelessWidget {
  const ShieldSheet({
    super.key,
    required this.engine,
    required this.settings,
    required this.vpn,
    required this.onOpenVpnScreen,
  });

  final BrowserEngine engine;
  final BrowserSettingsController settings;
  final VpnController vpn;
  final VoidCallback onOpenVpnScreen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[engine, settings, vpn]),
      builder: (BuildContext context, _) {
        final String? host = engine.currentHost;
        final bool hostTrusted = settings.isHostTrusted(host);
        final bool shieldEffective = settings.shieldEnabled && !hostTrusted;
        final List<String> blockedDomains = engine.pageBlockedDomains;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color:
                            (shieldEffective
                                    ? AppTheme.shieldEmerald
                                    : AppTheme.warningAmber)
                                .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        shieldEffective
                            ? Icons.shield_rounded
                            : Icons.shield_outlined,
                        color: shieldEffective
                            ? AppTheme.shieldEmerald
                            : AppTheme.warningAmber,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            shieldEffective
                                ? 'Heaven Shield Active'
                                : 'Heaven Shield Paused',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            host ?? 'Native Subresource & Tracker Firewall',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (host != null)
                      SiteLogo(urlOrDomain: host, size: 34, borderRadius: 10),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MetricTile(
                        label: 'Blocked on Page',
                        value: '${engine.pageBlockedCount}',
                        accent: AppTheme.shieldEmerald,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricTile(
                        label: 'Lifetime Blocked',
                        value: '${settings.totalTrackersBlocked}',
                        accent: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Heaven VPN Quick Banner inside Shield Sheet
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (vpn.isConnected
                                ? AppTheme.shieldEmerald
                                : colors.primary)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          (vpn.isConnected
                                  ? AppTheme.shieldEmerald
                                  : colors.primary)
                              .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        vpn.isConnected
                            ? Icons.vpn_lock_rounded
                            : Icons.vpn_key_outlined,
                        color: vpn.isConnected
                            ? AppTheme.shieldEmerald
                            : colors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            onOpenVpnScreen();
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                vpn.isConnected
                                    ? 'Heaven VPN Connected'
                                    : 'Heaven Free VPN (Off)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                vpn.isConnected
                                    ? '${vpn.selectedProfile.name} • Silent'
                                    : vpn.selectedProfile.countryLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: vpn.isConnected,
                        onChanged: vpn.isBusy
                            ? null
                            : (_) => vpn.toggleConnection(),
                      ),
                    ],
                  ),
                ),
                if (blockedDomains.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    'Intercepted Ad & Tracker Domains (${blockedDomains.length})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String d in blockedDomains.take(12))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.fireCrimson.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.fireCrimson.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            d,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(),
                if (host != null)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Protect $host'),
                    subtitle: Text(
                      hostTrusted
                          ? 'Ads & trackers allowed on this site'
                          : 'Blocking subresource ads, popups & trackers',
                    ),
                    value: !hostTrusted,
                    onChanged: settings.shieldEnabled
                        ? (_) async {
                            await settings.toggleHostTrust(host);
                            await engine.reloadOrStop();
                          }
                        : null,
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Global Heaven Shield'),
                  subtitle: const Text(
                    'Native network ad-blocker, video ad skipper & cosmetic filter',
                  ),
                  value: settings.shieldEnabled,
                  onChanged: (bool value) async {
                    await settings.setShieldEnabled(value);
                    if (!engine.isShowingStartPage &&
                        !engine.isShowingHeavenSearch) {
                      await engine.reloadOrStop();
                    }
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('HTTPS-First Upgrade'),
                  subtitle: const Text(
                    'Automatically upgrade insecure HTTP links',
                  ),
                  value: settings.httpsUpgrade,
                  onChanged: settings.setHttpsUpgrade,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
