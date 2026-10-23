import 'package:flutter/material.dart';

import '../utils/omnibox_parser.dart';

/// Tiny Search Engine Quick-Switcher button placed directly inside the Search Bar
/// so users can switch between Heaven Search, Google, DuckDuckGo, Brave, Bing,
/// and Startpage in a single tap.
class SearchEngineChipButton extends StatelessWidget {
  const SearchEngineChipButton({
    super.key,
    required this.currentEngine,
    required this.onSelected,
  });

  final SearchEngine currentEngine;
  final ValueChanged<SearchEngine> onSelected;

  static Color _engineColor(SearchEngine engine) {
    return switch (engine) {
      SearchEngine.heaven => const Color(0xFF2563EB),
      SearchEngine.google => const Color(0xFF4285F4),
      SearchEngine.duckDuckGo => const Color(0xFFDE5833),
      SearchEngine.brave => const Color(0xFFFB542B),
      SearchEngine.bing => const Color(0xFF008373),
      SearchEngine.startpage => const Color(0xFF6573FF),
    };
  }

  static String _engineBadgeText(SearchEngine engine) {
    return switch (engine) {
      SearchEngine.heaven => 'H',
      SearchEngine.google => 'G',
      SearchEngine.duckDuckGo => 'D',
      SearchEngine.brave => 'Br',
      SearchEngine.bing => 'Bi',
      SearchEngine.startpage => 'Sp',
    };
  }

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = _engineColor(currentEngine);
    return PopupMenuButton<SearchEngine>(
      key: const Key('tiny_search_engine_switcher'),
      tooltip: 'Switch Search Engine (${currentEngine.label})',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (BuildContext context) {
        return SearchEngine.values.map((SearchEngine engine) {
          final bool active = engine == currentEngine;
          final Color c = _engineColor(engine);
          return PopupMenuItem<SearchEngine>(
            value: engine,
            child: Row(
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _engineBadgeText(engine),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: c,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    engine.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (active)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: badgeColor.withValues(alpha: 0.42)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _engineBadgeText(currentEngine),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: badgeColor,
            ),
          ],
        ),
      ),
    );
  }
}
