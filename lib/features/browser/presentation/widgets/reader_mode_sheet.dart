import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../settings/browser_settings.dart';
import '../../engine/browser_engine.dart';
import '../../page_translate_reader_service.dart';

enum _ReaderPalette {
  midnight(label: 'Midnight', bg: Color(0xFF040B16), fg: Color(0xFFE8EEF8)),
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

  static _ReaderPalette fromKey(String key) {
    for (final _ReaderPalette p in _ReaderPalette.values) {
      if (p.name == key) return p;
    }
    return _ReaderPalette.midnight;
  }
}

class ReaderModeSheet extends StatefulWidget {
  const ReaderModeSheet({super.key, required this.article, this.settings});

  final ReadableArticle article;
  final BrowserSettingsController? settings;

  @override
  State<ReaderModeSheet> createState() => _ReaderModeSheetState();
}

class _ReaderModeSheetState extends State<ReaderModeSheet> {
  late double _fontSize;
  late _ReaderPalette _palette;
  bool _isTranslating = false;
  bool _isTranslated = false;
  String? _translatedTitle;
  List<String>? _translatedParagraphs;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings?.readerFontSize ?? 18.0;
    _palette = _ReaderPalette.fromKey(
      widget.settings?.readerTheme ?? 'midnight',
    );
  }

  int _estimateReadMinutes() {
    final int words = widget.article.paragraphs
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .length;
    return (words / 210).ceil().clamp(1, 90);
  }

  Future<void> _toggleReaderTranslation() async {
    if (_isTranslated) {
      setState(() {
        _isTranslated = false;
        _translatedTitle = null;
        _translatedParagraphs = null;
      });
      return;
    }
    final String targetLang = widget.settings?.translateTargetLang ?? 'en';
    setState(() => _isTranslating = true);
    try {
      final List<String> input = <String>[
        widget.article.title,
        ...widget.article.paragraphs,
      ];
      final List<String> out =
          await PageTranslateReaderService.translateSegments(
            input,
            targetLang: targetLang,
          );
      if (!mounted) return;
      if (out.isNotEmpty) {
        setState(() {
          _translatedTitle = out.first;
          _translatedParagraphs = out.sublist(1);
          _isTranslated = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String activeTitle = _translatedTitle ?? widget.article.title;
    final List<String> activeParagraphs =
        _translatedParagraphs ?? widget.article.paragraphs;
    final TranslateLanguage targetLang =
        PageTranslateReaderService.languageByCode(
          widget.settings?.translateTargetLang ?? 'en',
        );

    return Container(
      key: const Key('clean_reader_view_modal'),
      height: MediaQuery.of(context).size.height * 0.91,
      decoration: BoxDecoration(
        color: _palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 10, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.auto_stories_rounded,
                    color: _palette.fg.withValues(alpha: 0.85),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clean Reader • ${_estimateReadMinutes()} min read',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette.fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  for (final _ReaderPalette p in _ReaderPalette.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          setState(() => _palette = p);
                          widget.settings?.setReaderTheme(p.name);
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: p.bg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _palette == p
                                  ? AppTheme.heavenAccent
                                  : Colors.grey.withValues(alpha: 0.6),
                              width: _palette == p ? 2.2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    key: const Key('reader_translate_button'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                    icon: _isTranslating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.translate_rounded,
                            color: _isTranslated
                                ? AppTheme.heavenAccent
                                : _palette.fg,
                            size: 19,
                          ),
                    tooltip: _isTranslated
                        ? 'Show Original'
                        : 'Translate (${targetLang.name})',
                    onPressed: _isTranslating ? null : _toggleReaderTranslation,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      Icons.text_decrease_rounded,
                      color: _palette.fg,
                      size: 19,
                    ),
                    tooltip: 'Smaller text',
                    onPressed: () {
                      final double next = (_fontSize - 1.5).clamp(14.0, 26.0);
                      setState(() => _fontSize = next);
                      widget.settings?.setReaderFontSize(next);
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      Icons.text_increase_rounded,
                      color: _palette.fg,
                      size: 19,
                    ),
                    tooltip: 'Larger text',
                    onPressed: () {
                      final double next = (_fontSize + 1.5).clamp(14.0, 26.0);
                      setState(() => _fontSize = next);
                      widget.settings?.setReaderFontSize(next);
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 36,
                    ),
                    icon: Icon(Icons.close_rounded, color: _palette.fg, size: 20),
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
                    activeTitle,
                    style: TextStyle(
                      color: _palette.fg,
                      fontSize: _fontSize + 6,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final String p in activeParagraphs)
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
