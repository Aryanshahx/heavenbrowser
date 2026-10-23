import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/omnibox_parser.dart';
import '../../core/widgets/site_logo.dart';
import '../downloads/downloads_controller.dart';
import '../downloads/downloads_screen.dart';
import '../extensions/extensions_controller.dart';
import '../extensions/extensions_screen.dart';
import '../shield/native_shield_bridge.dart';
import '../tabs/tab_manager.dart';
import 'browser_settings.dart';
import 'help_screen.dart';
import 'languages_screen.dart';
import 'notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.tabManager,
    this.extensions,
    this.downloads,
  });

  final BrowserSettingsController settings;
  final TabManagerController tabManager;
  final ExtensionsController? extensions;
  final DownloadsController? downloads;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: <Widget>[
                Card(
                  elevation: 0,
                  color: colors.primaryContainer.withValues(alpha: 0.28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: colors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        AppConstants.logoAssetPath,
                        width: 38,
                        height: 38,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.public_rounded, color: colors.primary),
                      ),
                    ),
                    title: const Text(
                      'Set as Default Browser',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Open web links from all Android apps in Heaven Browser',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                    onTap: () async {
                      final bool opened = await NativeShieldBridge.instance
                          .openDefaultBrowserSettings();
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Open Android Settings > Apps > Default apps > Browser app',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('Search Engine', colors),
                _SettingsCard(
                  children: <Widget>[
                    RadioGroup<SearchEngine>(
                      groupValue: settings.searchEngine,
                      onChanged: (SearchEngine? val) {
                        if (val != null) {
                          settings.setSearchEngine(val);
                        }
                      },
                      child: Column(
                        children: <Widget>[
                          for (final SearchEngine engine in SearchEngine.values)
                            RadioListTile<SearchEngine>(
                              value: engine,
                              secondary: SiteLogo(
                                urlOrDomain: engine.homeUrl,
                                size: 28,
                                borderRadius: 8,
                              ),
                              title: Text(
                                engine == SearchEngine.heaven
                                    ? '${engine.label} (Default)'
                                    : engine.label,
                              ),
                              subtitle: Text(
                                engine == SearchEngine.heaven
                                    ? 'Web, Images, Videos, Live News & Instant Math'
                                    : engine.homeUrl,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Heaven Shield & Privacy', colors),
                _SettingsCard(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      title: const Text('Heaven Native Ad & Tracker Shield'),
                      subtitle: const Text(
                        'Blocks ad scripts, banners, popups & trackers at the network layer',
                      ),
                      value: settings.shieldEnabled,
                      onChanged: settings.setShieldEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('HTTPS-First Upgrade'),
                      subtitle: const Text(
                        'Automatically upgrade HTTP links to encrypted HTTPS',
                      ),
                      value: settings.httpsUpgrade,
                      onChanged: settings.setHttpsUpgrade,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Block Third-Party Cookies'),
                      subtitle: const Text(
                        'Prevent cross-site tracking cookies across tabs',
                      ),
                      value: settings.blockThirdPartyCookies,
                      onChanged: settings.setBlockThirdPartyCookies,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Send Do Not Track & GPC'),
                      subtitle: const Text(
                        'Broadcast Global Privacy Control opt-out signals',
                      ),
                      value: settings.sendDntAndGpc,
                      onChanged: settings.setSendDntAndGpc,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Auto-Burn When App Backgrounded'),
                      subtitle: const Text(
                        'Wipe tabs, cookies & storage when leaving app',
                      ),
                      value: settings.clearOnExit,
                      onChanged: settings.setClearOnExit,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Appearance & Toolbar', colors),
                _SettingsCard(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Theme',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const <ButtonSegment<ThemeMode>>[
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.system,
                                  label: Text('Auto'),
                                ),
                              ],
                              selected: <ThemeMode>{settings.themeMode},
                              onSelectionChanged: (Set<ThemeMode> modes) {
                                settings.setThemeMode(modes.first);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Top Address & Search Dock'),
                      subtitle: const Text(
                        'Keep search bar, Home & Forward controls at the top (Default)',
                      ),
                      value: !settings.bottomOmnibox,
                      onChanged: (bool topSelected) {
                        settings.setBottomOmnibox(!topSelected);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('JavaScript Engine'),
                      subtitle: const Text('Allow interactive web apps to run'),
                      value: settings.javascriptEnabled,
                      onChanged: settings.setJavascriptEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Desktop Site Mode'),
                      subtitle: const Text(
                        'Render full 1280px desktop layouts with pinch-zoom',
                      ),
                      value: settings.desktopMode,
                      onChanged: (bool value) {
                        tabManager.activeEngine.setDesktopModeAndReload(value);
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              const Text(
                                'Page Text Zoom',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text('${settings.textScalePercent}%'),
                            ],
                          ),
                          Slider(
                            value: settings.textScalePercent.toDouble(),
                            min: 75,
                            max: 175,
                            divisions: 20,
                            label: '${settings.textScalePercent}%',
                            onChanged: (double v) {
                              settings.setTextScalePercent(v.round());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Touch Gestures', colors),
                _SettingsCard(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      title: const Text('Enable App Touch Gestures'),
                      subtitle: const Text(
                        'Swipe address bar & screen edges for fast one-hand navigation',
                      ),
                      value: settings.gesturesEnabled,
                      onChanged: settings.setGesturesEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Swipe Address Bar to Switch Tabs'),
                      subtitle: const Text(
                        'Slide left/right on address bar for adjacent tabs, swipe up for Tab Grid',
                      ),
                      value: settings.barSwipeSwitchTabs,
                      onChanged: settings.gesturesEnabled
                          ? settings.setBarSwipeSwitchTabs
                          : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Edge Swipe Back & Forward'),
                      subtitle: const Text(
                        'Swipe inward from left/right screen edge to navigate history',
                      ),
                      value: settings.edgeSwipeNavigation,
                      onChanged: settings.gesturesEnabled
                          ? settings.setEdgeSwipeNavigation
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Extensions, Languages & Tools', colors),
                _SettingsCard(
                  children: <Widget>[
                    if (extensions != null) ...<Widget>[
                      ListTile(
                        leading: const Icon(Icons.extension_rounded),
                        title: const Text('Browser Extensions'),
                        subtitle: Text(
                          '${extensions!.enabledCount} active • Chrome Web Store (.crx) & .zip MV2/MV3',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ExtensionsScreen(
                              extensions: extensions!,
                              activeEngine: tabManager.activeEngine,
                              onOpenWebStoreInBrowser: () {
                                Navigator.pop(context);
                                tabManager.activeEngine.loadUserEntry(
                                  ExtensionsController.chromeWebStoreHomeUrl,
                                );
                              },
                              onOpenUrlInNewTab: (String url) {
                                tabManager.openNewTab(
                                  incognito: tabManager.isActiveIncognito,
                                  initialInput: url,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    if (downloads != null) ...<Widget>[
                      ListTile(
                        leading: const Icon(Icons.folder_open_rounded),
                        title: const Text('Download Location'),
                        subtitle: Text(downloads!.downloadLocationPath),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DownloadsScreen(downloads: downloads!),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: const Text(
                        'Download alerts, website notifications & silent VPN',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NotificationsScreen(settings: settings),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.translate_rounded),
                      title: const Text('Languages'),
                      subtitle: Text(
                        '${settings.language.nativeLabel} (${settings.language.englishLabel})',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LanguagesScreen(settings: settings),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded),
                      title: const Text('Help & Support'),
                      subtitle: const Text(HelpScreen.supportEmail),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const HelpScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Data & Privacy Cleanup', colors),
                _SettingsCard(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.history_toggle_off_rounded),
                      title: const Text('Clear History & Visited Sites'),
                      subtitle: Text(
                        '${settings.history.length} history entries saved',
                      ),
                      onTap: () async {
                        await settings.clearUsageAndHistory();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'History and visited sites cleared',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.local_fire_department_rounded,
                        color: colors.error,
                      ),
                      title: Text(
                        'Burn All Tabs, Cookies & Storage',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'Closes every tab and scrubs WebView cache & cookies',
                      ),
                      onTap: () async {
                        await tabManager.burnAllSessionsAndData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'All tabs, cookies, cache & history burned',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('About', colors),
                _SettingsCard(
                  children: const <Widget>[
                    ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text(AppConstants.appName),
                      subtitle: Text('Version ${AppConstants.appVersion}'),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.inventory_2_outlined),
                      title: Text('Package ID'),
                      subtitle: Text(AppConstants.packageName),
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
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.colors);

  final String text;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
