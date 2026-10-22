import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/site_logo.dart';
import 'tab_manager.dart';

class TabSwitcherSheet extends StatefulWidget {
  const TabSwitcherSheet({super.key, required this.tabManager});

  final TabManagerController tabManager;

  @override
  State<TabSwitcherSheet> createState() => _TabSwitcherSheetState();
}

class _TabSwitcherSheetState extends State<TabSwitcherSheet> {
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
        final List<BrowserTab> tabs = _viewingIncognito
            ? widget.tabManager.incognitoTabs
            : widget.tabManager.normalTabs;

        return Theme(
          data: theme,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.80,
            decoration: BoxDecoration(
              color: _viewingIncognito
                  ? const Color(0xFF120822)
                  : theme.bottomSheetTheme.backgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                value: false,
                                icon: const Icon(Icons.tab_rounded, size: 17),
                                label: Text(
                                  'Tabs (${widget.tabManager.normalTabs.length})',
                                ),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: const Icon(
                                  Icons.shield_moon_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  'Incognito (${widget.tabManager.incognitoTabs.length})',
                                ),
                              ),
                            ],
                            selected: <bool>{_viewingIncognito},
                            onSelectionChanged: (Set<bool> selection) {
                              setState(
                                () => _viewingIncognito = selection.first,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Done',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (_viewingIncognito)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.incognitoOrchid.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.incognitoOrchid.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.visibility_off_rounded,
                            size: 16,
                            color: AppTheme.incognitoOrchid,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Stealth Mode: zero browsing history, zero site-usage tracking, cookies wiped on close.',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: tabs.isEmpty
                        ? _buildEmptyModeState(context, colors)
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.05,
                                ),
                            itemCount: tabs.length,
                            itemBuilder: (BuildContext context, int index) {
                              return _buildTabCard(
                                context,
                                colors,
                                tabs[index],
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        if (tabs.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await widget.tabManager.closeAllTabsByMode(
                                incognito: _viewingIncognito,
                              );
                            },
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                            ),
                            label: const Text('Close All'),
                          ),
                        const Spacer(),
                        if (!_viewingIncognito) ...<Widget>[
                          OutlinedButton.icon(
                            onPressed: () async {
                              await widget.tabManager.openNewTab(
                                incognito: true,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            icon: const Icon(
                              Icons.shield_moon_outlined,
                              size: 17,
                            ),
                            label: const Text('Incognito'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton.icon(
                          onPressed: () async {
                            await widget.tabManager.openNewTab(
                              incognito: _viewingIncognito,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: Text(
                            _viewingIncognito ? 'New Incognito' : 'New Tab',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyModeState(BuildContext context, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _viewingIncognito
                  ? Icons.shield_moon_rounded
                  : Icons.tab_unselected_rounded,
              size: 48,
              color: colors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _viewingIncognito
                  ? 'No Incognito tabs open'
                  : 'No standard tabs open',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _viewingIncognito
                  ? 'Open a private Incognito tab to browse without saving history or cookies.'
                  : 'Tap New Tab below to start browsing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabCard(
    BuildContext context,
    ColorScheme colors,
    BrowserTab tab,
  ) {
    final bool isActive = widget.tabManager.activeTab.id == tab.id;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        widget.tabManager.switchToTab(tab.id);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tab.isIncognito
              ? const Color(0xFF1E1035)
              : (isDark
                    ? const Color(0xFF131D35)
                    : colors.surfaceContainerHighest.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.4),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SiteLogo(
                  urlOrDomain: tab.engine.currentUrl,
                  fallbackLabel: tab.displayTitle,
                  size: 28,
                  borderRadius: 8,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.displaySubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => widget.tabManager.closeTab(tab.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              tab.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (tab.isIncognito)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.incognitoOrchid.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'STEALTH',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.incognitoOrchid,
                      ),
                    ),
                  )
                else if (tab.engine.pageBlockedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.shieldEmerald.withValues(alpha: 0.16),
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
                  ),
                const Spacer(),
                if (isActive)
                  Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
