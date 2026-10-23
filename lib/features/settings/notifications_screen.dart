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

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _systemEnabled = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .getNotificationStatus();
    if (!mounted) return;
    setState(() {
      _systemEnabled = res['systemEnabled'] != false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.navySurface : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            _systemEnabled
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_off_rounded,
                            color: _systemEnabled
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _systemEnabled
                                  ? 'Android Notifications Allowed'
                                  : 'Android Notifications Blocked',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          if (!_systemEnabled) ...<Widget>[
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  await NativeShieldBridge.instance
                                      .requestNotificationPermission();
                                  await _refreshStatus();
                                },
                                child: const Text('Allow Permission'),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => NativeShieldBridge.instance
                                  .openNotificationSettings(),
                              child: const Text('Android Settings'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: isDark ? AppTheme.navySurface : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        secondary: Icon(
                          Icons.downloading_rounded,
                          color: colors.primary,
                        ),
                        title: const Text(
                          'Download Progress Alerts',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Show status bar progress while downloading large files',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: widget.settings.downloadNotificationsEnabled,
                        onChanged:
                            widget.settings.setDownloadNotificationsEnabled,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: Icon(
                          Icons.language_rounded,
                          color: colors.primary,
                        ),
                        title: const Text(
                          'Website Notifications',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Allow trusted sites to request web notifications',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: widget.settings.webNotificationsEnabled,
                        onChanged: widget.settings.setWebNotificationsEnabled,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.vpn_lock_rounded,
                          color: colors.primary,
                        ),
                        title: const Text(
                          'Stealth VPN Silent Mode',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Always silent — Heaven VPN never posts a persistent notification.',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
