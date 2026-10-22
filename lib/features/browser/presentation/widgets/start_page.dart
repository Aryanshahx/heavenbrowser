import 'package:flutter/material.dart';

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
    required this.onVoiceSearch,
  });

  final BrowserSettingsController settings;
  final bool isIncognito;
  final ValueChanged<String> onSelectUrl;
  final ValueChanged<String> onOpenInNewTab;
  final ValueChanged<String> onOpenInIncognitoTab;
  final VoidCallback onTapSearchBox;
  final VoidCallback onVoiceSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: settings,
      builder: (BuildContext context, _) {
        final List<SiteUsageEntry> visitedSites = settings.quickLaunchSites;

        return RefreshIndicator(
          onRefresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 220));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 44, 20, 32),
                sliver: SliverList.list(
                  children: <Widget>[
                    // Clean typography wordmark (no app icon, no clutter buttons)
                    Center(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) =>
                            (isIncognito
                                    ? AppTheme.incognitoGradient
                                    : AppTheme.brandGradient)
                                .createShader(bounds),
                        child: Text(
                          isIncognito ? 'Heaven Incognito' : 'Heaven',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _buildSearchCapsule(context, theme, colors, isDark),
                    if (!isIncognito && visitedSites.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 30),
                      _buildVisitedGrid(context, colors, isDark, visitedSites),
                    ],
                    if (isIncognito) ...<Widget>[
                      const SizedBox(height: 28),
                      _buildStealthNotice(colors),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
          ? (isIncognito ? const Color(0xFF131B2B) : const Color(0xFF140C29))
          : Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTapSearchBox,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.42),
              width: 1.3,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showQuickEnginePicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
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
                        size: 15,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search or type web address',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                onPressed: onVoiceSearch,
                icon: Icon(Icons.mic_rounded, color: colors.primary, size: 21),
                tooltip: 'Voice Search',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisitedGrid(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    List<SiteUsageEntry> items,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 520 ? 5 : 4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            mainAxisExtent: 86,
          ),
          itemBuilder: (BuildContext context, int index) {
            final SiteUsageEntry site = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelectUrl(site.url),
              onLongPress: () => _showQuickSiteOptions(context, site),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SiteLogo(
                    urlOrDomain: site.url,
                    fallbackLabel: site.title,
                    size: 44,
                    borderRadius: 14,
                  ),
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      site.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStealthNotice(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.incognitoCyan.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.incognitoCyan.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        'Pages you view in this Incognito tab will not stick around in your browser history, search history, or cookies after you close your Incognito tabs.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: colors.onSurface.withValues(alpha: 0.85),
        ),
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
                    'Search Engine',
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
                            size: 28,
                            borderRadius: 8,
                          ),
                          title: Text(
                            engine == SearchEngine.heaven
                                ? '${engine.label} (Default)'
                                : engine.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                subtitle: Text(site.domain),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  site.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(site.isPinned ? 'Unpin' : 'Pin Site'),
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
                  color: AppTheme.incognitoCyan,
                ),
                title: const Text('Open in Incognito Tab'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenInIncognitoTab(site.url);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.fireCrimson,
                ),
                title: const Text('Remove'),
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
}
