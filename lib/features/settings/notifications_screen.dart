import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shield/native_shield_bridge.dart';
import 'browser_settings.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.settings});

  final BrowserSettingsController settings;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  bool _systemEnabled = true;
  bool _runtimeGranted = true;
  bool _testingAlert = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .getNotificationStatus();
    if (!mounted) return;
    setState(() {
      _systemEnabled = res['systemEnabled'] != false;
      _runtimeGranted = res['runtimeGranted'] != false;
    });
  }

  Future<void> _sendTestNotification() async {
    setState(() => _testingAlert = true);
    if (!_systemEnabled || !_runtimeGranted) {
      await NativeShieldBridge.instance.requestNotificationPermission();
      await _refreshStatus();
    }
    final bool ok = await NativeShieldBridge.instance.sendTestNotification();
    if (!mounted) return;
    setState(() => _testingAlert = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Test notification delivered to your Android status bar!'
              : 'Enable Android notification permission first to receive alerts.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool fullyAllowed = _systemEnabled && _runtimeGranted;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notification Control Center',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Permission Status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: <Widget>[
                // Hero Status Banner
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: fullyAllowed
                          ? <Color>[
                              AppTheme.shieldEmerald.withValues(alpha: 0.20),
                              colors.primary.withValues(alpha: 0.14),
                            ]
                          : <Color>[
                              AppTheme.warningAmber.withValues(alpha: 0.22),
                              AppTheme.fireCrimson.withValues(alpha: 0.12),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color:
                          (fullyAllowed
                                  ? AppTheme.shieldEmerald
                                  : AppTheme.warningAmber)
                              .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color:
                                  (fullyAllowed
                                          ? AppTheme.shieldEmerald
                                          : AppTheme.warningAmber)
                                      .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              fullyAllowed
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_paused_rounded,
                              color: fullyAllowed
                                  ? AppTheme.shieldEmerald
                                  : AppTheme.warningAmber,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  fullyAllowed
                                      ? 'System Permission Active'
                                      : 'Notification Permission Needed',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fullyAllowed
                                      ? 'Android POST_NOTIFICATIONS is granted for downloads, media playback, and security alerts.'
                                      : 'Tap Grant Permission below so background downloads and media controls stay visible.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (!fullyAllowed)
                            FilledButton.icon(
                              key: const Key('grant_notification_perm_button'),
                              onPressed: () async {
                                await NativeShieldBridge.instance
                                    .requestNotificationPermission();
                                await _refreshStatus();
                              },
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Grant Permission'),
                            ),
                          FilledButton.tonalIcon(
                            key: const Key('send_test_notification_button'),
                            onPressed: _testingAlert
                                ? null
                                : _sendTestNotification,
                            icon: const Icon(
                              Icons.notification_add_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _testingAlert ? 'Sending...' : 'Send Test Alert',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => NativeShieldBridge.instance
                                .openNotificationSettings(),
                            icon: const Icon(Icons.tune_rounded, size: 17),
                            label: const Text('Android Settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildCategoryHeader('DOWNLOADS & BACKGROUND MEDIA', colors),
                const SizedBox(height: 8),
                _buildCard(
                  isDark,
                  colors,
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      secondary: Icon(
                        Icons.downloading_rounded,
                        color: colors.primary,
                      ),
                      title: const Text(
                        'File Download Progress & Completion',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Live speed, byte progress, and 1-tap open when finished',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: widget.settings.downloadNotificationsEnabled,
                      onChanged:
                          widget.settings.setDownloadNotificationsEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: Icon(
                        Icons.headphones_rounded,
                        color: colors.primary,
                      ),
                      title: const Text(
                        'Background Audio & Screen-Off Playback',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Keep YouTube, Twitch & web audio alive when screen is locked',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: widget.settings.backgroundPlayNotificationEnabled,
                      onChanged: widget
                          .settings
                          .setBackgroundPlayNotificationEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildCategoryHeader('PRIVACY, SECURITY & WEBSITES', colors),
                const SizedBox(height: 8),
                _buildCard(
                  isDark,
                  colors,
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      secondary: Icon(
                        Icons.gpp_good_rounded,
                        color: colors.primary,
                      ),
                      title: const Text(
                        'Anti-Redirect & Spam Hijack Alerts',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Show banner when Heaven blocks Play Store or ad hijacks',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: widget.settings.securityRedirectAlertsEnabled,
                      onChanged: widget.settings.setSecurityRedirectAlertsEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      secondary: Icon(
                        Icons.language_rounded,
                        color: colors.primary,
                      ),
                      title: const Text(
                        'Website Push Notifications',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Allow trusted websites to request browser push alerts (Off by default)',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: widget.settings.webNotificationsEnabled,
                      onChanged: widget.settings.setWebNotificationsEnabled,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.vpn_lock_rounded,
                        color: AppTheme.shieldEmerald,
                      ),
                      title: const Text(
                        'Foreign Country VPN Silent Tunnel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Always silent — Heaven VPN never clutters your tray with persistent alerts.',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.shieldEmerald.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'SILENT',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.shieldEmerald,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String title, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.85,
          color: colors.primary,
        ),
      ),
    );
  }

  Widget _buildCard(
    bool isDark,
    ColorScheme colors, {
    required List<Widget> children,
  }) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
