import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onClearAllBrowsingData,
  });

  final BrowserSettingsController settings;
  final Future<void> Function() onClearAllBrowsingData;

  Future<void> _copyDiagnostics(BuildContext context) async {
    final String report = <String>[
      'App: ${AppConstants.appName}',
      'Version: ${AppConstants.appVersion}',
      'Package: ${AppConstants.packageName}',
      'Platform: ${defaultTargetPlatform.name}',
      'Search Engine: ${settings.searchEngine.label}',
      'Heaven Shield: ${settings.shieldEnabled ? 'Enabled' : 'Disabled'}',
      'HTTPS Upgrade: ${settings.httpsUpgrade ? 'Enabled' : 'Disabled'}',
      'Repository: ${AppConstants.githubRepoUrl}',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (BuildContext context, _) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final TextTheme textTheme = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Browser Settings'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _SectionTitle(title: 'Appearance & Layout', colors: colors),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Theme',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const <ButtonSegment<ThemeMode>>[
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.brightness_auto_outlined),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode_outlined),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode_outlined),
                            ),
                          ],
                          selected: <ThemeMode>{settings.themeMode},
                          onSelectionChanged: (Set<ThemeMode> next) {
                            settings.setThemeMode(next.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Address Bar Position',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<OmniboxPosition>(
                          segments: const <ButtonSegment<OmniboxPosition>>[
                            ButtonSegment<OmniboxPosition>(
                              value: OmniboxPosition.bottom,
                              label: Text('Bottom'),
                              icon: Icon(Icons.vertical_align_bottom_rounded),
                            ),
                            ButtonSegment<OmniboxPosition>(
                              value: OmniboxPosition.top,
                              label: Text('Top'),
                              icon: Icon(Icons.vertical_align_top_rounded),
                            ),
                          ],
                          selected: <OmniboxPosition>{settings.omniboxPosition},
                          onSelectionChanged: (Set<OmniboxPosition> next) {
                            settings.setOmniboxPosition(next.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _SectionTitle(title: 'Search Engine', colors: colors),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Column(
                  children: SearchEngine.values.map((SearchEngine engine) {
                    final bool isSelected = settings.searchEngine == engine;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected ? colors.primary : null,
                      ),
                      title: Text(engine.label),
                      subtitle: Text(engine.homeUrl),
                      onTap: () => settings.setSearchEngine(engine),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              _SectionTitle(title: 'Heaven Shield & Privacy', colors: colors),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('Block Trackers & Ads'),
                      subtitle: const Text(
                        'Blocks analytics beacons, ad networks & Global Privacy Control',
                      ),
                      value: settings.shieldEnabled,
                      onChanged: settings.setShieldEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Smart HTTPS Upgrade'),
                      subtitle: const Text(
                        'Automatically upgrades HTTP links to encrypted HTTPS',
                      ),
                      value: settings.httpsUpgrade,
                      onChanged: settings.setHttpsUpgrade,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Block Third-Party Cookies'),
                      subtitle: const Text(
                        'Prevents cross-site tracking cookies in WebView',
                      ),
                      value: settings.blockThirdPartyCookies,
                      onChanged: settings.setBlockThirdPartyCookies,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(
                        'Total Trackers Blocked: ${settings.totalTrackersBlocked}',
                      ),
                      trailing: TextButton(
                        onPressed: settings.totalTrackersBlocked > 0
                            ? settings.resetBlockedCounter
                            : null,
                        child: const Text('Reset'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.local_fire_department_rounded,
                        color: colors.error,
                      ),
                      title: const Text('Clear Cookies, Cache & Storage Now'),
                      onTap: () async {
                        await onClearAllBrowsingData();
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cookies, cache & site storage cleared',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _SectionTitle(title: 'Site Content', colors: colors),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('Enable JavaScript'),
                      subtitle: const Text('Required by most modern web apps'),
                      value: settings.javascriptEnabled,
                      onChanged: settings.setJavascriptEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Desktop Site by Default'),
                      subtitle: const Text('Request desktop layouts on load'),
                      value: settings.desktopMode,
                      onChanged: settings.setDesktopMode,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Page Text Size'),
                      subtitle: Text('${settings.textZoom}%'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Decrease text size',
                            onPressed: settings.textZoom > 75
                                ? () => settings
                                    .setTextZoom(settings.textZoom - 10)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          IconButton(
                            tooltip: 'Increase text size',
                            onPressed: settings.textZoom < 150
                                ? () => settings
                                    .setTextZoom(settings.textZoom + 10)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: const Text('Restore Default Quick Shortcuts'),
                      onTap: () async {
                        await settings.resetDefaultShortcuts();
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Default shortcuts restored'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _SectionTitle(title: 'About Heaven Browser', colors: colors),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${AppConstants.appName} v${AppConstants.appVersion}',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        AppConstants.packageName,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _copyDiagnostics(context),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy Build Info'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.colors,
  });

  final String title;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
