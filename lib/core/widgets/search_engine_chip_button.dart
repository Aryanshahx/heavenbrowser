import 'package:flutter/material.dart';

import '../utils/omnibox_parser.dart';

/// Renders the real bundled brand logo image for a [SearchEngine].
class SearchEngineLogo extends StatelessWidget {
  const SearchEngineLogo({
    super.key,
    required this.engine,
    this.size = 20,
    this.borderRadius = 6,
  });

  final SearchEngine engine;
  final double size;
  final double borderRadius;

  static Color engineColor(SearchEngine engine) {
    return switch (engine) {
      SearchEngine.google => const Color(0xFF4285F4),
      SearchEngine.perplexity => const Color(0xFF20B8CD),
      SearchEngine.duckDuckGo => const Color(0xFFDE5833),
      SearchEngine.brave => const Color(0xFFFB542B),
      SearchEngine.bing => const Color(0xFF008373),
      SearchEngine.startpage => const Color(0xFF6573FF),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Color c = engineColor(engine);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        engine.logoAssetPath,
        key: Key('search_engine_logo_${engine.name}'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Text(
            engine.badge,
            style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.w900,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchEngineMenuAction {
  const _SearchEngineMenuAction({
    required this.engine,
    required this.openOwnSettings,
  });

  final SearchEngine engine;
  final bool openOwnSettings;
}

/// Search Engine Quick-Switcher button placed directly inside the Search Bar
/// showing the real brand image of Google, Perplexity, DuckDuckGo,
/// Brave, Bing, or Startpage — plus direct 1-tap access to each search
/// engine's own real settings page!
class SearchEngineChipButton extends StatelessWidget {
  const SearchEngineChipButton({
    super.key,
    required this.currentEngine,
    required this.onSelected,
    this.onOpenEngineSettings,
  });

  final SearchEngine currentEngine;
  final ValueChanged<SearchEngine> onSelected;
  final ValueChanged<SearchEngine>? onOpenEngineSettings;

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = SearchEngineLogo.engineColor(currentEngine);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return PopupMenuButton<_SearchEngineMenuAction>(
      key: const Key('tiny_search_engine_switcher'),
      tooltip: 'Switch Search Engine (${currentEngine.label})',
      onSelected: (_SearchEngineMenuAction action) {
        if (action.openOwnSettings && onOpenEngineSettings != null) {
          onOpenEngineSettings!(action.engine);
        } else {
          onSelected(action.engine);
        }
      },
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (BuildContext menuContext) {
        final List<PopupMenuEntry<_SearchEngineMenuAction>> entries =
            <PopupMenuEntry<_SearchEngineMenuAction>>[];
        for (final SearchEngine engine in SearchEngine.values) {
          final bool active = engine == currentEngine;
          entries.add(
            PopupMenuItem<_SearchEngineMenuAction>(
              key: Key('popup_search_engine_${engine.name}'),
              value: _SearchEngineMenuAction(
                engine: engine,
                openOwnSettings: false,
              ),
              child: Row(
                children: <Widget>[
                  SearchEngineLogo(engine: engine, size: 22, borderRadius: 6),
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
                  if (active) ...<Widget>[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    if (onOpenEngineSettings != null) const SizedBox(width: 4),
                  ],
                  if (onOpenEngineSettings != null)
                    InkWell(
                      key: Key('popup_engine_settings_${engine.name}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(menuContext).pop();
                        onOpenEngineSettings!(engine);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Tooltip(
                          message: '${engine.label} Settings',
                          child: Icon(
                            Icons.tune_rounded,
                            size: 17,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        // NOTE: the old bottom "X Settings" entry was removed — per-engine
        // gears (popup_engine_settings_<name>) are the only settings access
        // in this picker now.
        return entries;
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: badgeColor.withValues(alpha: 0.36)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SearchEngineLogo(
              engine: currentEngine,
              size: 18,
              borderRadius: 9,
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
