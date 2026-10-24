import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../settings/browser_settings.dart';
import '../shield/brave_shield_status.dart';
import '../shield/native_shield_bridge.dart';
import 'engine/browser_engine.dart';

class SiteControlsSheet extends StatefulWidget {
  const SiteControlsSheet({
    super.key,
    required this.engine,
    required this.settings,
  });

  final BrowserEngine engine;
  final BrowserSettingsController settings;

  static Future<void> show(
    BuildContext context, {
    required BrowserEngine engine,
    required BrowserSettingsController settings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SiteControlsSheet(engine: engine, settings: settings),
    );
  }

  static IconData _iconForPermission(SitePermissionType type) {
    return switch (type) {
      SitePermissionType.location => Icons.location_on_outlined,
      SitePermissionType.camera => Icons.videocam_outlined,
      SitePermissionType.microphone => Icons.mic_none_rounded,
      SitePermissionType.notifications => Icons.notifications_outlined,
      SitePermissionType.popups => Icons.open_in_new_off_rounded,
      SitePermissionType.javascript => Icons.javascript_rounded,
      SitePermissionType.protectedMedia => Icons.enhanced_encryption_outlined,
    };
  }

  @override
  State<SiteControlsSheet> createState() => _SiteControlsSheetState();
}

class _SiteControlsSheetState extends State<SiteControlsSheet> {
  BraveShieldStats _shieldStats = const BraveShieldStats();

  BrowserEngine get engine => widget.engine;
  BrowserSettingsController get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _loadShieldStats();
  }

  Future<void> _loadShieldStats() async {
    final BraveShieldStats fetched = await NativeShieldBridge.instance
        .getBraveShieldStats(webViewId: engine.androidWebViewId ?? -1);
    if (mounted) {
      setState(() => _shieldStats = fetched);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[engine, settings]),
      builder: (BuildContext context, _) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final String? host = engine.currentHost;
        final String displayHost = (host != null && host.isNotEmpty)
            ? host
            : 'Current Tab';
        final bool hasWebHost = host != null && host.isNotEmpty;

        final List<SitePermissionType> dashboardPermissions =
            const <SitePermissionType>[
              SitePermissionType.location,
              SitePermissionType.camera,
              SitePermissionType.microphone,
              SitePermissionType.notifications,
              SitePermissionType.popups,
              SitePermissionType.javascript,
              SitePermissionType.protectedMedia,
            ];

        final int activeSensitiveCount = hasWebHost
            ? <SitePermissionType>[
                    SitePermissionType.location,
                    SitePermissionType.camera,
                    SitePermissionType.microphone,
                    SitePermissionType.notifications,
                    SitePermissionType.popups,
                  ]
                  .where(
                    (SitePermissionType t) =>
                        settings.getSitePermission(host, t) ==
                        SitePermissionDecision.allow,
                  )
                  .length
            : 0;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              (engine.isSecure ? Colors.green : Colors.orange)
                                  .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          engine.isSecure
                              ? Icons.verified_user_rounded
                              : Icons.info_outline_rounded,
                          color: engine.isSecure ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              displayHost,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              engine.isSecure
                                  ? 'Encrypted HTTPS • Per-Site Permission Dashboard'
                                  : 'Local or unencrypted page',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasWebHost && activeSensitiveCount > 0)
                        FilledButton.tonalIcon(
                          key: const Key('revoke_all_site_permissions_button'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: colors.error,
                          ),
                          onPressed: () async {
                            await settings.revokeAllPermissionsForSite(host);
                            await engine.reloadFullPage();
                          },
                          icon: const Icon(Icons.gpp_bad_outlined, size: 16),
                          label: const Text('Revoke All'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildBraveShieldsCard(
                    colors,
                    isDark: isDark,
                    host: host,
                    hasWebHost: hasWebHost,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  const Text(
                    'PER-SITE HARDWARE & WEB PERMISSIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.navySurface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (
                          int i = 0;
                          i < dashboardPermissions.length;
                          i++
                        ) ...<Widget>[
                          if (i > 0) const Divider(height: 1),
                          _buildPermissionRow(
                            context,
                            colors,
                            host: host,
                            hasWebHost: hasWebHost,
                            type: dashboardPermissions[i],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.desktop_windows_rounded,
                      color: colors.primary,
                    ),
                    title: const Text(
                      'Desktop Site',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    value: settings.desktopMode,
                    onChanged: (bool v) => engine.setDesktopModeAndReload(v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.format_size_rounded, color: colors.primary),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Page Text Size',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => settings.setTextScalePercent(
                            settings.textScalePercent - 10,
                          ),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                        Text(
                          '${settings.textScalePercent}%',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          onPressed: () => settings.setTextScalePercent(
                            settings.textScalePercent + 10,
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (hasWebHost) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await NativeShieldBridge.instance.clearSiteData(
                          domain: host,
                        );
                        await engine.reloadFullPage();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Cleared cookies & site data for $host',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cleaning_services_rounded),
                      label: const Text('Clear Site Cookies & Storage'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBraveShieldsCard(
    ColorScheme colors, {
    required bool isDark,
    required String? host,
    required bool hasWebHost,
  }) {
    final bool shieldsUp = settings.isBraveShieldEnabledForHost(host);
    final int blocked = hasWebHost
        ? _shieldStats.tabBlocked
        : _shieldStats.totalBlocked;
    final int surrogates = hasWebHost
        ? _shieldStats.tabSurrogates
        : _shieldStats.totalSurrogates;

    final String subtitleText = shieldsUp
        ? '$blocked ads & trackers blocked'
              '${surrogates > 0 ? ' • $surrogates SugarCoat' : ''}'
              '${settings.farblingEnabled ? ' • Farbling on' : ''}'
        : 'Shields Down for ${hasWebHost ? host : 'all sites'}';

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: shieldsUp
              ? AppTheme.shieldEmerald.withValues(alpha: 0.45)
              : colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile.adaptive(
        key: const Key('site_brave_shields_switch'),
        dense: true,
        secondary: Icon(
          shieldsUp ? Icons.shield_rounded : Icons.shield_outlined,
          color: shieldsUp ? AppTheme.shieldEmerald : colors.onSurfaceVariant,
          size: 21,
        ),
        title: const Text(
          'Brave Shields',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.8),
        ),
        subtitle: Text(
          subtitleText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        value: shieldsUp,
        onChanged: (bool value) async {
          if (hasWebHost && host != null) {
            if (value && !settings.braveShieldsEnabled) {
              await settings.setBraveShieldsEnabled(true);
            }
            await settings.setBraveShieldForHost(host, value);
            await engine.reloadFullPage();
          } else {
            await settings.setBraveShieldsEnabled(value);
          }
          await _loadShieldStats();
        },
      ),
    );
  }

  Widget _buildPermissionRow(
    BuildContext context,
    ColorScheme colors, {
    required String? host,
    required bool hasWebHost,
    required SitePermissionType type,
  }) {
    final SitePermissionDecision decision = settings.getSitePermission(
      host,
      type,
    );
    final Color badgeColor = switch (decision) {
      SitePermissionDecision.allow => AppTheme.shieldEmerald,
      SitePermissionDecision.block => AppTheme.fireCrimson,
      SitePermissionDecision.ask => colors.primary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: <Widget>[
            Icon(SiteControlsSheet._iconForPermission(type), size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  type.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  type.description,
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
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              decision.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (decision == SitePermissionDecision.allow)
            TextButton(
              key: Key('revoke_perm_${type.name}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                foregroundColor: colors.error,
              ),
              onPressed: hasWebHost
                  ? () async {
                      await settings.revokeSitePermission(host!, type);
                      await engine.reloadFullPage();
                    }
                  : null,
              child: const Text(
                'Revoke',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            )
          else
            TextButton(
              key: Key('allow_perm_${type.name}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              onPressed: hasWebHost
                  ? () async {
                      await settings.setSitePermission(
                        host!,
                        type,
                        SitePermissionDecision.allow,
                      );
                      await engine.reloadFullPage();
                    }
                  : null,
              child: const Text(
                'Allow',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
