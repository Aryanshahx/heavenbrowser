import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    Navigator.of(context).pop();
    await tabManager.openNewTab(
      incognito: tabManager.isActiveIncognito,
      initialInput: AppConstants.privacyPolicyUrl,
    );
  }

  Future<void> _toggleBiometricSetting(
    BuildContext context, {
    required bool currentValue,
    required Future<void> Function(bool) onApply,
    required String reason,
  }) async {
    final bool ok = await NativeShieldBridge.instance.authenticateBiometric(
      reason: reason,
    );
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up Fingerprint, Face Unlock, or Screen Lock in Android Settings first.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await onApply(!currentValue);
  }

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
                                engine == SearchEngine.google
                                    ? '${engine.label} (Default)'
                                    : engine.label,
                              ),
                              subtitle: Text(
                                engine.homeUrl,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Ergonomic One-Handed UI & Gestures', colors),
                _SettingsCard(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      title: const Text('Bottom Navigation Bar (Default)'),
                      subtitle: const Text(
                        'Keep address bar, tab switcher & menus in easy thumb reach at the bottom',
                      ),
                      value: settings.bottomOmnibox,
                      onChanged: settings.setBottomOmnibox,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Floating Quick Action Button'),
                      subtitle: const Text(
                        '1-tap corner button for Refresh, Bookmark, Media, PiP & Desktop Mode',
                      ),
                      value: settings.quickActionEnabled,
                      onChanged: settings.setQuickActionEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Left-Handed Quick Action Corner'),
                      subtitle: const Text(
                        'Place Quick Action button in bottom-left instead of bottom-right',
                      ),
                      value: settings.quickActionLeftHanded,
                      onChanged: settings.quickActionEnabled
                          ? settings.setQuickActionLeftHanded
                          : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Swipe Address Bar to Switch Tabs'),
                      subtitle: const Text(
                        'Swipe left/right on address bar to switch tabs, swipe up for Tab Grid',
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
                _SectionTitle('Media & Background Handling', colors),
                _SettingsCard(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      title: const Text('True Background Audio & Video'),
                      subtitle: const Text(
                        'Keep YouTube, Twitch & video platforms playing with screen locked',
                      ),
                      value: settings.backgroundMediaEnabled,
                      onChanged: settings.setBackgroundMediaEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Auto Picture-in-Picture (PiP)'),
                      subtitle: const Text(
                        'Automatically pop playing videos into Android PiP when pressing Home',
                      ),
                      value: settings.autoPipEnabled,
                      onChanged: settings.setAutoPipEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Data Control & Mobile Performance', colors),
                _SettingsCard(
                  children: <Widget>[
                    ListTile(
                      leading: Icon(
                        Icons.savings_outlined,
                        color: colors.primary,
                      ),
                      title: Text(
                        'Cellular Data Saved: ${settings.formattedDataSaved}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${settings.totalTrackersBlocked} ad/tracker requests & heavy assets blocked',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Text-Only / Ultra Data Saver Mode'),
                      subtitle: const Text(
                        'Blocks network images, video posters & heavy fonts for instant cellular loads',
                      ),
                      value: settings.ultraDataSaverMode,
                      onChanged: (bool val) async {
                        await settings.setUltraDataSaverMode(val);
                        if (!tabManager.activeEngine.isShowingStartPage) {
                          await tabManager.activeEngine.reloadFullPage();
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Aggressive Tab Hibernation'),
                      subtitle: Text(
                        'Automatically sleep inactive tabs after ${settings.tabHibernationMinutes} min to save RAM & battery',
                      ),
                      value: settings.tabHibernationEnabled,
                      onChanged: settings.setTabHibernationEnabled,
                    ),
                    if (settings.tabHibernationEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Row(
                          children: <Widget>[
                            const Text(
                              'Sleep Timeout',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            Expanded(
                              child: Slider(
                                value: settings.tabHibernationMinutes
                                    .toDouble(),
                                min: 1,
                                max: 15,
                                divisions: 14,
                                label: '${settings.tabHibernationMinutes} min',
                                onChanged: (double v) => settings
                                    .setTabHibernationMinutes(v.round()),
                              ),
                            ),
                            Text('${settings.tabHibernationMinutes}m'),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Mobile Privacy & App Security', colors),
                _SettingsCard(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      title: const Text('Biometric Lock for Incognito Tabs'),
                      subtitle: const Text(
                        'Require Fingerprint or Face Unlock before viewing Incognito tabs',
                      ),
                      value: settings.biometricLockIncognito,
                      onChanged: (_) => _toggleBiometricSetting(
                        context,
                        currentValue: settings.biometricLockIncognito,
                        onApply: settings.setBiometricLockIncognito,
                        reason:
                            'Verify biometrics to configure Incognito Tab Lock',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Biometric Lock for Entire App'),
                      subtitle: const Text(
                        'Lock Heaven Browser with Fingerprint or Face Unlock on startup',
                      ),
                      value: settings.biometricLockApp,
                      onChanged: (_) => _toggleBiometricSetting(
                        context,
                        currentValue: settings.biometricLockApp,
                        onApply: settings.setBiometricLockApp,
                        reason:
                            'Verify biometrics to configure Heaven App Lock',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Automatic Anti-Redirects'),
                      subtitle: Text(
                        'Block ads from hijacking pages to Play Store or spam sites (${settings.antiRedirectsBlockedCount} blocked)',
                      ),
                      value: settings.antiRedirectProtection,
                      onChanged: settings.setAntiRedirectProtection,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Heaven Native Ad & Tracker Shield'),
                      subtitle: const Text(
                        'Blocks ad scripts, banners, YouTube ads & trackers at the network layer',
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
                      title: const Text('Auto-Burn Tabs & Data on Exit'),
                      subtitle: const Text(
                        'Optional: wipe tabs, cookies & storage when leaving app (Off by default so tabs stay open)',
                      ),
                      value: settings.clearOnExit,
                      onChanged: settings.setClearOnExit,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionTitle('Appearance & Rendering', colors),
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
                        'Permission status, download & media playback alerts',
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
                      key: const Key('settings_privacy_policy_tile'),
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Policy'),
                      subtitle: const Text(
                        'github.com/Aryanshahx/heavenbrowser/blob/main/privacypolicy.md',
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => _openPrivacyPolicy(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded),
                      title: const Text('Help & Support'),
                      subtitle: const Text(HelpScreen.supportEmail),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HelpScreen(
                            onOpenUrlInBrowser: (String url) {
                              Navigator.of(context).pop();
                              tabManager.openNewTab(
                                incognito: tabManager.isActiveIncognito,
                                initialInput: url,
                              );
                            },
                          ),
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
                  children: <Widget>[
                    const ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text(AppConstants.appName),
                      subtitle: Text('Version ${AppConstants.appVersion}'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.inventory_2_outlined),
                      title: Text('Package ID'),
                      subtitle: Text(AppConstants.packageName),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.policy_outlined),
                      title: const Text('Official Privacy Policy'),
                      subtitle: const Text(AppConstants.privacyPolicyUrl),
                      trailing: const Icon(Icons.launch_rounded, size: 17),
                      onTap: () => launchUrl(
                        Uri.parse(AppConstants.privacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
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
