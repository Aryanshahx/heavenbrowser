import 'package:flutter/material.dart';

import '../settings/browser_settings.dart';
import '../shield/native_shield_bridge.dart';
import 'engine/browser_engine.dart';

class SiteControlsSheet extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[engine, settings]),
      builder: (BuildContext context, _) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final String? host = engine.currentHost;
        final String displayHost =
            (host != null && host.isNotEmpty) ? host : 'Current Tab';
        final bool hasWebHost = host != null && host.isNotEmpty;
        final bool shieldOnForSite =
            settings.shieldEnabled && !settings.isHostTrusted(host);
        final bool jsAllowed = settings.isJavaScriptAllowedForHost(host);
        final bool popupsBlocked = settings.arePopupsBlockedForHost(host);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (engine.isSecure ? Colors.green : Colors.orange)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        engine.isSecure
                            ? Icons.lock_rounded
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
                                ? 'Encrypted HTTPS connection'
                                : 'Local or unencrypted page',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.shield_rounded, color: colors.primary),
                  title: const Text(
                    'Heaven Shield for this site',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${engine.pageBlockedCount} ads & trackers blocked on this page',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: shieldOnForSite,
                  onChanged: hasWebHost
                      ? (_) async {
                          await settings.toggleHostTrust(host);
                          await engine.reloadFullPage();
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.javascript_rounded, color: colors.primary),
                  title: const Text(
                    'Allow JavaScript on this site',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Disable to stop heavy scripts or paywall overlays',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: jsAllowed,
                  onChanged: hasWebHost
                      ? (_) async {
                          await settings.toggleSiteJavaScript(host);
                          await engine.reloadFullPage();
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.block_rounded, color: colors.primary),
                  title: const Text(
                    'Block Pop-ups & Redirect Windows',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Prevents unwanted window.open pop-ups',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: popupsBlocked,
                  onChanged: hasWebHost
                      ? (_) async {
                          await settings.toggleSitePopups(host);
                          await engine.reloadFullPage();
                        }
                      : null,
                ),
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
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                            content: Text('Cleared cookies & site data for $host'),
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
        );
      },
    );
  }
}
