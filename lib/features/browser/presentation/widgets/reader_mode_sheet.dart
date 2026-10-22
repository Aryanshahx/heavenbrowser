import 'package:flutter/material.dart';

import '../../engine/browser_engine.dart';

enum _ReaderPalette {
  obsidian(label: 'Obsidian', bg: Color(0xFF0A0F1D), fg: Color(0xFFE5ECF6)),
  sepia(label: 'Sepia', bg: Color(0xFFF6EFE2), fg: Color(0xFF2B2118)),
  paper(label: 'Paper', bg: Color(0xFFFFFFFF), fg: Color(0xFF111827));

  const _ReaderPalette({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;
}

class ReaderModeSheet extends StatefulWidget {
  const ReaderModeSheet({super.key, required this.article});

  final ReadableArticle article;

  @override
  State<ReaderModeSheet> createState() => _ReaderModeSheetState();
}

class _ReaderModeSheetState extends State<ReaderModeSheet> {
  double _fontSize = 17;
  _ReaderPalette _palette = _ReaderPalette.obsidian;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: _palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.menu_book_rounded,
                    color: _palette.fg.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Heaven Reader',
                    style: TextStyle(
                      color: _palette.fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  for (final _ReaderPalette p in _ReaderPalette.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(() => _palette = p),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: p.bg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _palette == p
                                  ? const Color(0xFF00E5FF)
                                  : Colors.grey,
                              width: _palette == p ? 2.2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.text_decrease_rounded, color: _palette.fg),
                    tooltip: 'Smaller text',
                    onPressed: () => setState(
                      () => _fontSize = (_fontSize - 1.5).clamp(13.0, 26.0),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.text_increase_rounded, color: _palette.fg),
                    tooltip: 'Larger text',
                    onPressed: () => setState(
                      () => _fontSize = (_fontSize + 1.5).clamp(13.0, 26.0),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: _palette.fg),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _palette.fg.withValues(alpha: 0.14)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
                children: <Widget>[
                  if (widget.article.siteName.isNotEmpty)
                    Text(
                      widget.article.siteName.toUpperCase(),
                      style: TextStyle(
                        color: _palette.fg.withValues(alpha: 0.6),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    widget.article.title,
                    style: TextStyle(
                      color: _palette.fg,
                      fontSize: _fontSize + 7,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final String p in widget.article.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(
                        p,
                        style: TextStyle(
                          color: _palette.fg.withValues(alpha: 0.92),
                          fontSize: _fontSize,
                          height: 1.62,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
