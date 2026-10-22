import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/omnibox_parser.dart';

class SiteLogo extends StatelessWidget {
  const SiteLogo({
    super.key,
    required this.urlOrDomain,
    this.fallbackLabel,
    this.size = 38,
    this.borderRadius = 12,
  });

  final String? urlOrDomain;
  final String? fallbackLabel;
  final double size;
  final double borderRadius;

  static const List<List<Color>> _brandPalettes = <List<Color>>[
    <Color>[Color(0xFF00E5FF), Color(0xFF2563EB)],
    <Color>[Color(0xFF8B5CF6), Color(0xFFEC4899)],
    <Color>[Color(0xFF10B981), Color(0xFF059669)],
    <Color>[Color(0xFFF59E0B), Color(0xFFEA580C)],
    <Color>[Color(0xFF3B82F6), Color(0xFF6366F1)],
    <Color>[Color(0xFFEF4444), Color(0xFFBE123C)],
  ];

  @override
  Widget build(BuildContext context) {
    final String raw = (urlOrDomain ?? '').trim();
    if (raw.isEmpty || OmniboxParser.isHeavenSearchUrl(raw)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          AppConstants.logoAssetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildMonogram('H', 'heaven'),
        ),
      );
    }

    final String domain = OmniboxParser.cleanDomain(raw);
    if (domain.isEmpty || !domain.contains('.')) {
      return _buildMonogram(fallbackLabel ?? raw, raw);
    }

    final String primaryUrl =
        'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(domain)}&sz=128';
    final String secondaryUrl =
        'https://icons.duckduckgo.com/ip3/${Uri.encodeComponent(domain)}.ico';

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.09)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius * 0.55),
        child: Image.network(
          primaryUrl,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) {
            return Image.network(
              secondaryUrl,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _buildMonogram(
                fallbackLabel ?? domain,
                domain,
                compact: true,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMonogram(String label, String seed, {bool compact = false}) {
    final String clean = label.trim();
    final String letter = clean.isEmpty ? 'W' : clean[0].toUpperCase();
    final int paletteIdx =
        seed.codeUnits.fold<int>(0, (int a, int b) => a + b) %
        _brandPalettes.length;
    final List<Color> colors = _brandPalettes[paletteIdx];

    return Container(
      width: compact ? null : size,
      height: compact ? null : size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          compact ? borderRadius * 0.55 : borderRadius,
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.44,
          height: 1,
        ),
      ),
    );
  }
}
