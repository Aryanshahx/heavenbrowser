import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/omnibox_parser.dart';
import '../../../../core/widgets/site_logo.dart';
import '../../../settings/browser_settings.dart';

class StartPage extends StatelessWidget {
  const StartPage({
    super.key,
    required this.settings,
    required this.isIncognito,
    required this.onSelectUrl,
    required this.onOpenInNewTab,
    required this.onOpenInIncognitoTab,
    required this.onTapSearchBox,
    required this.onOpenBookmarks,
    required this.onOpenHistory,
    required this.onToggleIncognitoNewTab,
  });

  final BrowserSettingsController settings;
  final bool isIncognito;
  final ValueChanged<String> onSelectUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final VoidCallback onTapSearchBox;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onOpenHistory;
  final VoidCallback onToggleIncognitoNewTab;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: settings,
      builder: (BuildContext context, _) {
        final List<SiteUsageEntry> quickSites = settings.quickLaunchSites;

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
              sliver: SliverList.list(
                children: <Widget>[
                  _buildTopBar(context, colors),
                  const SizedBox(height: 22),
                  _buildHeroIdentity(context, theme, colors),
                  const SizedBox(height: 22),
                  _buildSearchCapsule(context, theme, colors, isDark),
                  const SizedBox(height: 16),
                  _buildTelemetryDeck(context, colors, isDark),
                  const SizedBox(height: 24),
                  if (!isIncognito) ...<Widget>[
                    _buildQuickLaunchHeader(context, theme, colors),
                    const SizedBox(height: 12),
                    _buildQuickLaunchGrid(context, colors, isDark, quickSites),
                  ] else
                    _buildIncognitoInfoCard(context, colors),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, ColorScheme colors) {
    return Row(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onOpenBookmarks,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.bookmarks_outlined, size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  'Bookmarks (${settings.bookmarks.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!isIncognito)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenHistory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.history_rounded, size: 15, color: colors.primary),
                  const SizedBox(width: 5),
                  const Text(
                    'History',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onToggleIncognitoNewTab,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: isIncognito ? AppTheme.incognitoGradient : null,
              color: isIncognito
                  ? null
                  : AppTheme.incognitoOrchid.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.incognitoOrchid.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.shield_moon_rounded,
                  size: 15,
                  color: isIncognito ? Colors.white : AppTheme.incognitoOrchid,
                ),
                const SizedBox(width: 5),
                Text(
                  isIncognito ? 'Stealth Active' : '+ Incognito',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isIncognito
                        ? Colors.white
                        : AppTheme.incognitoOrchid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroIdentity(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Row(
      children: <Widget>[
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color:
                    (isIncognito ? AppTheme.incognitoOrchid : AppTheme.neonCyan)
                        .withValues(alpha: 0.28),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: isIncognito
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.incognitoGradient,
                    ),
                    child: const Icon(
                      Icons.shield_moon_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  )
                : Image.asset(
                    AppConstants.logoAssetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isIncognito ? 'Heaven Stealth' : AppConstants.appName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isIncognito
                    ? 'Zero history • Zero usage trace • Full ad shield'
                    : 'Private by design • Powered by ${settings.searchEngine.label}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchCapsule(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
  ) {
    return Material(
      color: isDark
          ? (isIncognito ? const Color(0xFF1A0E2E) : const Color(0xFF10192E))
          : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTapSearchBox,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.38),
              width: 1.3,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showQuickEnginePicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SiteLogo(
                        urlOrDomain: settings.searchEngine.homeUrl,
                        size: 18,
                        borderRadius: 5,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        settings.searchEngine.shortLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search with ${settings.searchEngine.label} or enter URL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                size: 20,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryDeck(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:
                  (settings.shieldEnabled
                          ? AppTheme.shieldEmerald
                          : AppTheme.warningAmber)
                      .withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              settings.shieldEnabled
                  ? Icons.verified_user_rounded
                  : Icons.shield_outlined,
              color: settings.shieldEnabled
                  ? AppTheme.shieldEmerald
                  : AppTheme.warningAmber,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  settings.shieldEnabled
                      ? 'Heaven Native Ad-Shield Armed'
                      : 'Heaven Ad-Shield Paused',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${settings.totalTrackersBlocked} ads, trackers & popups intercepted',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: settings.shieldEnabled,
            onChanged: settings.setShieldEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLaunchHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Smart Quick Launch',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Auto-ranked by your most visited sites • Hold any tile for options',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _showPinSiteDialog(context),
          icon: const Icon(Icons.push_pin_outlined, size: 16),
          label: const Text('Pin Site'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }

  Widget _buildQuickLaunchGrid(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    List<SiteUsageEntry> items,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.80,
      ),
      itemBuilder: (BuildContext context, int index) {
        final SiteUsageEntry site = items[index];

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onSelectUrl(site.url),
          onLongPress: () => _showQuickSiteOptions(context, site),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0E1629)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: site.isPinned
                    ? colors.primary.withValues(alpha: 0.45)
                    : colors.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    SiteLogo(
                      urlOrDomain: site.url,
                      fallbackLabel: site.title,
                      size: 40,
                      borderRadius: 13,
                    ),
                    if (site.isPinned || site.visitCount > 0)
                      Positioned(
                        right: -6,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: site.isPinned
                                ? colors.primary
                                : AppTheme.shieldEmerald,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: site.isPinned
                              ? const Icon(
                                  Icons.push_pin_rounded,
                                  size: 9,
                                  color: Colors.black,
                                )
                              : Text(
                                  '${site.visitCount}×',
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  site.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIncognitoInfoCard(BuildContext context, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.incognitoOrchid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.incognitoOrchid.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.visibility_off_rounded,
                color: AppTheme.incognitoOrchid,
                size: 22,
              ),
              SizedBox(width: 10),
              Text(
                'Stealth Incognito Guarantees',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• Websites visited in this tab never appear in History or Quick Launch.\n'
            '• Third-party tracking cookies are strictly blocked.\n'
            '• Heaven Native Ad-Shield remains active against ads & trackers.\n'
            '• Closing your last Incognito tab wipes session cookies & storage.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colors.onSurface.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickEnginePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Active Search Engine',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                RadioGroup<SearchEngine>(
                  groupValue: settings.searchEngine,
                  onChanged: (SearchEngine? engine) {
                    if (engine != null) {
                      settings.setSearchEngine(engine);
                    }
                    Navigator.pop(sheetContext);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final SearchEngine engine in SearchEngine.values)
                        RadioListTile<SearchEngine>(
                          value: engine,
                          secondary: SiteLogo(
                            urlOrDomain: engine.homeUrl,
                            size: 30,
                            borderRadius: 8,
                          ),
                          title: Text(
                            engine == SearchEngine.heaven
                                ? '${engine.label} (Built-in Default)'
                                : engine.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            engine == SearchEngine.heaven
                                ? 'Instant native private search with zero external redirect'
                                : engine.homeUrl,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuickSiteOptions(
    BuildContext context,
    SiteUsageEntry site,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: SiteLogo(urlOrDomain: site.url, size: 36),
                title: Text(
                  site.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  site.visitCount > 0
                      ? '${site.domain} • Visited ${site.visitCount} times'
                      : site.domain,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  site.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  site.isPinned ? 'Unpin from Top' : 'Pin to Quick Launch',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  settings.togglePinQuickSite(site.domain);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Open in New Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenInNewTab(site.url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.shield_moon_outlined,
                  color: AppTheme.incognitoOrchid,
                ),
                title: const Text('Open in Incognito Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenInIncognitoTab(site.url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: AppTheme.fireCrimson,
                ),
                title: const Text('Remove from Quick Launch'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  settings.removeQuickLaunchSite(site.domain);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPinSiteDialog(BuildContext context) async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController urlCtrl = TextEditingController();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Pin Website to Quick Launch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. Proton Mail',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Domain or URL',
                  hintText: 'proton.me',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Pin'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && urlCtrl.text.trim().isNotEmpty) {
      await settings.pinOrAddQuickLaunchSite(
        title: titleCtrl.text,
        rawUrl: urlCtrl.text,
      );
    }
    titleCtrl.dispose();
    urlCtrl.dispose();
  }
}
