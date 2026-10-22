import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/site_logo.dart';
import 'tab_manager.dart';

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key, required this.tabManager});

  final TabManagerController tabManager;

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  late bool _viewingIncognito;

  @override
  void initState() {
    super.initState();
    _viewingIncognito = widget.tabManager.isActiveIncognito;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tabManager,
      builder: (BuildContext context, _) {
        final ThemeData theme = _viewingIncognito
            ? AppTheme.incognitoTheme
            : Theme.of(context);
        final ColorScheme colors = theme.colorScheme;
        final bool isDark = theme.brightness == Brightness.dark;
        final List<BrowserTab> tabs = _viewingIncognito
            ? widget.tabManager.incognitoTabs
            : widget.tabManager.normalTabs;

        return Theme(
          data: theme,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Back to browser',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              titleSpacing: 0,
              title: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _buildModeToggleBar(colors, isDark),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  if (_viewingIncognito)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.incognitoCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.incognitoCyan.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.shield_moon_rounded,
                            size: 18,
                            color: AppTheme.incognitoCyan,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Incognito Mode: History, search queries, and site usage are never saved.',
                              style: TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: tabs.isEmpty
                        ? _buildEmptyState(context, colors)
                        : LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final int columns =
                                      constraints.maxWidth >= 620 ? 3 : 2;
                                  return GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      8,
                                      14,
                                      18,
                                    ),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          mainAxisExtent: 216,
                                        ),
                                    itemCount: tabs.length,
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                          return _buildFullTabWindowCard(
                                            context,
                                            colors,
                                            isDark,
                                            tabs[index],
                                          );
                                        },
                                  );
                                },
                          ),
                  ),
                  _buildBottomBar(context, colors, tabs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeToggleBar(ColorScheme colors, bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ModeTabButton(
              selected: !_viewingIncognito,
              icon: Icons.tab_rounded,
              label: 'Tabs (${widget.tabManager.normalTabs.length})',
              accent: colors.primary,
              onTap: () => setState(() => _viewingIncognito = false),
            ),
          ),
          Expanded(
            child: _ModeTabButton(
              selected: _viewingIncognito,
              icon: Icons.shield_moon_rounded,
              label: 'Incognito (${widget.tabManager.incognitoTabs.length})',
              accent: AppTheme.incognitoCyan,
              onTap: () => setState(() => _viewingIncognito = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                _viewingIncognito
                    ? Icons.shield_moon_rounded
                    : Icons.tab_rounded,
                size: 34,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _viewingIncognito
                  ? 'No Incognito tabs open'
                  : 'No standard tabs open',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _viewingIncognito
                  ? 'Tap New Incognito below to browse privately with zero saved trace.'
                  : 'Tap New Tab below to start browsing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullTabWindowCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    BrowserTab tab,
  ) {
    final bool isActive = widget.tabManager.activeTab.id == tab.id;
    final Color cardBg = tab.isIncognito
        ? const Color(0xFF131B2B)
        : (isDark ? const Color(0xFF150D2A) : Colors.white);
    final Color headerBg = tab.isIncognito
        ? const Color(0xFF1D283D)
        : (isDark
              ? const Color(0xFF21153F)
              : colors.surfaceContainerHighest.withValues(alpha: 0.65));

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          widget.tabManager.switchToTab(tab.id);
          Navigator.pop(context);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.4),
              width: isActive ? 2.2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Top window title bar
              Container(
                height: 40,
                padding: const EdgeInsets.only(left: 10, right: 4),
                color: headerBg,
                child: Row(
                  children: <Widget>[
                    SiteLogo(
                      urlOrDomain: tab.engine.currentUrl,
                      fallbackLabel: tab.displayTitle,
                      size: 20,
                      borderRadius: 6,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tab.displaySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      tooltip: 'Close tab',
                      onPressed: () => widget.tabManager.closeTab(tab.id),
                    ),
                  ],
                ),
              ),
              // Full window preview body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: SiteLogo(
                          urlOrDomain: tab.engine.currentUrl,
                          fallbackLabel: tab.displayTitle,
                          size: 44,
                          borderRadius: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tab.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          height: 1.28,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: <Widget>[
                          if (tab.engine.pageBlockedCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.shieldEmerald.withValues(
                                  alpha: 0.16,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(
                                    Icons.shield_rounded,
                                    size: 11,
                                    color: AppTheme.shieldEmerald,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${tab.engine.pageBlockedCount}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.shieldEmerald,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Icon(
                              tab.isIncognito
                                  ? Icons.visibility_off_outlined
                                  : (tab.engine.isSecure
                                        ? Icons.lock_outline_rounded
                                        : Icons.public_rounded),
                              size: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          const Spacer(),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'OPEN',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: colors.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ColorScheme colors,
    List<BrowserTab> tabs,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: tabs.isNotEmpty
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        children: <Widget>[
          if (tabs.isNotEmpty)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await widget.tabManager.closeAllTabsByMode(
                      incognito: _viewingIncognito,
                    );
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                  label: const Text('Close All'),
                ),
              ),
            ),
          if (tabs.isNotEmpty) const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  await widget.tabManager.openNewTab(
                    incognito: _viewingIncognito,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: Icon(
                  _viewingIncognito
                      ? Icons.shield_moon_rounded
                      : Icons.add_rounded,
                  size: 19,
                ),
                label: Text(_viewingIncognito ? 'New Incognito' : 'New Tab'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: accent.withValues(alpha: 0.55))
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected
                    ? accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
