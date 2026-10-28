import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../../core/widgets/search_engine_chip_button.dart';
import '../downloads/downloads_controller.dart';
import '../shield/native_shield_bridge.dart';
import '../tabs/tab_manager.dart';
import '../vpn/vpn_controller.dart';
import '../vpn/vpn_screen.dart';
import 'browser_settings.dart';
import 'help_screen.dart';
import 'languages_screen.dart';
import 'notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.tabManager,
    this.downloads,
    this.vpn,
  });

  final BrowserSettingsController settings;
  final TabManagerController tabManager;
  final DownloadsController? downloads;
  final VpnController? vpn;

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    Navigator.of(context).pop();
    await tabManager.openNewTab(
      incognito: tabManager.isActiveIncognito,
      initialInput: AppConstants.privacyPolicyUrl,
    );
  }

  Future<void> _openSearchEngineOwnSettings(
    BuildContext context,
    SearchEngine engine,
  ) async {
    await settings.setSearchEngine(engine);
    if (context.mounted) {
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    }
    await tabManager.activeEngine.loadUri(Uri.parse(engine.settingsUrl));
  }

  Future<void> _pickSearchEngine(BuildContext context) async {
    final ColorScheme colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Search Engine & Engine Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap an engine to apply it, or tap its tune icon to customize its own search settings.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final SearchEngine engine in SearchEngine.values)
                  ListTile(
                    key: Key('search_engine_option_${engine.name}'),
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: SearchEngineLogo(
                      engine: engine,
                      size: 26,
                      borderRadius: 7,
                    ),
                    title: Text(
                      engine.label,
                      style: TextStyle(
                        fontWeight: settings.searchEngine == engine
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      engine.settingsSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (settings.searchEngine == engine) ...<Widget>[
                          Icon(
                            Icons.check_circle_rounded,
                            size: 19,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          key: Key('open_engine_own_settings_${engine.name}'),
                          tooltip: '${engine.label} Settings',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: () =>
                              _openSearchEngineOwnSettings(sheetContext, engine),
                          icon: Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await settings.setSearchEngine(engine);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                      final active = tabManager.activeEngine;
                      if (active.isShowingWebPage) {
                        final String q = OmniboxParser.extractSearchOrSiteQuery(
                          currentUrl: active.currentUrl,
                          pageTitle: active.pageTitle,
                        );
                        unawaited(active.loadUri(engine.buildSearchUri(q)));
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: vpn != null
              ? Listenable.merge(<Listenable>[settings, vpn!])
              : settings,
          builder: (BuildContext context, _) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: <Widget>[
                _MinimalSectionLabel('General', colors),
                _MinimalGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    ListTile(
                      key: const Key('settings_search_engine_tile'),
                      dense: true,
                      leading: SearchEngineLogo(
                        engine: settings.searchEngine,
                        size: 24,
                        borderRadius: 7,
                      ),
                      title: const Text('Search Engine'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            settings.searchEngine.shortLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      onTap: () => _pickSearchEngine(context),
                    ),
                    _thinDivider(colors),
                    ListTile(
                      key: const Key('settings_active_engine_own_settings_tile'),
                      dense: true,
                      leading: Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: Text('${settings.searchEngine.label} Settings'),
                      subtitle: Text(
                        settings.searchEngine.settingsSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      onTap: () => _openSearchEngineOwnSettings(
                        context,
                        settings.searchEngine,
                      ),
                    ),
                    _thinDivider(colors),
                    ListTile(
                      key: const Key('settings_default_browser_tile'),
                      dense: true,
                      leading: Icon(
                        Icons.public_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: const Text('Default Browser'),
                      subtitle: const Text(
                        'Open web links automatically in Heaven',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      onTap: () {
                        unawaited(
                          NativeShieldBridge.instance
                              .requestDefaultBrowserRole(),
                        );
                      },
                    ),
                    _thinDivider(colors),
                    ListTile(
                      key: const Key('settings_add_widget_tile'),
                      dense: true,
                      leading: Icon(
                        Icons.widgets_outlined,
                        size: 20,
                        color: colors.primary,
                      ),
                      title: const Text('Add Search Widget'),
                      subtitle: const Text(
                        'Pin Heaven Search bar widget to your Home Screen',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      trailing: Icon(
                        Icons.add_circle_outline_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      onTap: () async {
                        final ScaffoldMessengerState? messenger =
                            ScaffoldMessenger.maybeOf(context);
                        final bool pinned = await NativeShieldBridge.instance
                            .requestPinSearchWidget();
                        if (!pinned) {
                          messenger?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Long-press your Home Screen → Widgets → select "Heaven Search"',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    if (vpn != null) ...<Widget>[
                      _thinDivider(colors),
                      ListTile(
                        key: const Key('settings_vpn_tile'),
                        dense: true,
                        leading: Icon(
                          Icons.vpn_lock_rounded,
                          size: 20,
                          color: vpn!.isConnected
                              ? AppTheme.shieldEmerald
                              : colors.primary,
                        ),
                        title: const Text('Heaven VPN'),
                        subtitle: Text(
                          vpn!.isConnected
                              ? 'Connected • ${vpn!.selectedProfile.flagEmoji} ${vpn!.selectedProfile.name}'
                              : 'Disconnected • ${vpn!.selectedProfile.flagEmoji} ${vpn!.selectedProfile.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              vpn!.isConnected ? 'ON' : 'OFF',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: vpn!.isConnected
                                    ? AppTheme.shieldEmerald
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HeavenVpnScreen(vpn: vpn!),
                            ),
                          );
                        },
                      ),
                    ],
                    _thinDivider(colors),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.contrast_rounded, size: 20),
                          const SizedBox(width: 12),
                          const Text('Theme'),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SegmentedButton<ThemeMode>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                  ),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                    _thinDivider(colors),
                    SwitchListTile.adaptive(
                      dense: true,
                      secondary: const Icon(
                        Icons.headphones_rounded,
                        size: 20,
                      ),
                      title: const Text('Background Audio'),
                      subtitle: const Text(
                        'Keep playback active when screen is off',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: settings.backgroundMediaEnabled,
                      onChanged: settings.setBackgroundMediaEnabled,
                    ),
                    _thinDivider(colors),
                    SwitchListTile.adaptive(
                      dense: true,
                      secondary: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 20,
                      ),
                      title: const Text('Desktop Site'),
                      value: settings.desktopMode,
                      onChanged: (bool value) {
                        tabManager.activeEngine.setDesktopModeAndReload(value);
                      },
                    ),
                    _thinDivider(colors),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.format_size_rounded, size: 20),
                          const SizedBox(width: 14),
                          const Text('Text Size'),
                          Expanded(
                            child: Slider(
                              value: settings.textScalePercent.toDouble(),
                              min: 75,
                              max: 175,
                              divisions: 20,
                              onChanged: (double v) {
                                settings.setTextScalePercent(v.round());
                              },
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${settings.textScalePercent}%',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _MinimalSectionLabel('Tools', colors),
                _MinimalGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    if (downloads != null) ...<Widget>[
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.folder_open_rounded,
                          size: 20,
                        ),
                        title: const Text('Downloads'),
                        subtitle: Text(
                          downloads!.downloadLocationPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          tabManager.openDownloadsTab();
                        },
                      ),
                      _thinDivider(colors),
                    ],
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.notifications_none_rounded,
                        size: 20,
                      ),
                      title: const Text('Notifications'),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NotificationsScreen(settings: settings),
                        ),
                      ),
                    ),
                    _thinDivider(colors),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.translate_rounded, size: 20),
                      title: const Text('Language'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            settings.language.nativeLabel,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LanguagesScreen(settings: settings),
                        ),
                      ),
                    ),
                    _thinDivider(colors),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.public_rounded, size: 20),
                      title: const Text('Default Browser'),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
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
                  ],
                ),
                const SizedBox(height: 18),
                _MinimalSectionLabel('Data & About', colors),
                _MinimalGroup(
                  isDark: isDark,
                  colors: colors,
                  children: <Widget>[
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.history_toggle_off_rounded,
                        size: 20,
                      ),
                      title: const Text('Clear Browsing History'),
                      trailing: Text(
                        '${settings.history.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      onTap: () async {
                        await settings.clearUsageAndHistory();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('History cleared'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    _thinDivider(colors),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.local_fire_department_outlined,
                        size: 20,
                        color: colors.error,
                      ),
                      title: Text(
                        'Burn All Tabs & Site Data',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w600,
                        ),
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
                    _thinDivider(colors),
                    ListTile(
                      key: const Key('settings_privacy_policy_tile'),
                      dense: true,
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        size: 20,
                      ),
                      title: const Text('Privacy Policy'),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      onTap: () => _openPrivacyPolicy(context),
                    ),
                    _thinDivider(colors),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.help_outline_rounded, size: 20),
                      title: const Text('Help & Support'),
                      subtitle: const Text(
                        HelpScreen.supportEmail,
                        style: TextStyle(fontSize: 11.5),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
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
                    _thinDivider(colors),
                    ListTile(
                      dense: true,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          AppConstants.logoAssetPath,
                          width: 22,
                          height: 22,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.public_rounded, color: colors.primary),
                        ),
                      ),
                      title: const Text(
                        AppConstants.appName,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(
                        'v${AppConstants.appVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _thinDivider(ColorScheme colors) => Divider(
    height: 1,
    indent: 50,
    color: colors.outlineVariant.withValues(alpha: 0.28),
  );
}

class _MinimalSectionLabel extends StatelessWidget {
  const _MinimalSectionLabel(this.title, this.colors);

  final String title;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MinimalGroup extends StatelessWidget {
  const _MinimalGroup({
    required this.isDark,
    required this.colors,
    required this.children,
  });

  final bool isDark;
  final ColorScheme colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
