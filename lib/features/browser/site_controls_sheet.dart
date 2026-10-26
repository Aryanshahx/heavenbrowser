import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../settings/browser_settings.dart';
import 'engine/browser_engine.dart';
import 'page_translate_reader_service.dart';

class TranslateReaderSheet extends StatefulWidget {
  const TranslateReaderSheet({
    super.key,
    required this.engine,
    required this.settings,
  });

  final BrowserEngine engine;
  final BrowserSettingsController settings;

  @override
  State<TranslateReaderSheet> createState() => _TranslateReaderSheetState();
}

class _TranslateReaderSheetState extends State<TranslateReaderSheet> {
  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String host = OmniboxParser.cleanDomain(widget.engine.currentUrl);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.settings, widget.engine]),
      builder: (BuildContext context, _) {
        final String selectedLangCode = widget.settings.translateTargetLang;
        final TranslateLanguage selectedLang =
            PageTranslateReaderService.languageByCode(selectedLangCode);
        final bool isTranslated = widget.engine.isPageTranslated;
        final bool isTranslating = widget.engine.isTranslatingPage;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              key: const Key('translate_reader_sheet'),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.heavenAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: AppTheme.heavenAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Translate Page',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              host.isEmpty
                                  ? 'Translate webpages in-place without reloading'
                                  : 'Translate $host in-place',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTranslated)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.shieldEmerald.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.engine.translatedLangCode?.toUpperCase() ??
                                selectedLang.code.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.shieldEmerald,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          PageTranslateReaderService.supportedLanguages.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(width: 7),
                      itemBuilder: (BuildContext context, int index) {
                        final TranslateLanguage lang =
                            PageTranslateReaderService
                                .supportedLanguages[index];
                        final bool selected =
                            lang.code.toLowerCase() ==
                            selectedLangCode.toLowerCase();
                        return ChoiceChip(
                          key: Key('translate_lang_chip_${lang.code}'),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          label: Text(
                            lang.name == lang.nativeLabel
                                ? lang.name
                                : '${lang.name} • ${lang.nativeLabel}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : colors.onSurface,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AppTheme.heavenBlue,
                          backgroundColor: colors.surfaceContainerHigh,
                          showCheckmark: false,
                          onSelected: (_) {
                            widget.settings.setTranslateTargetLang(lang.code);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('translate_page_now_button'),
                          onPressed:
                              (!widget.engine.isShowingWebPage || isTranslating)
                              ? null
                              : () async {
                                  final ScaffoldMessengerState messenger =
                                      ScaffoldMessenger.of(context);
                                  final bool ok = await widget.engine
                                      .translateCurrentPage(selectedLang.code);
                                  if (!mounted) return;
                                  messenger
                                    ..clearSnackBars()
                                    ..showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? 'Translated to ${selectedLang.name}'
                                              : 'Unable to translate this page right now',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(
                                          milliseconds: 1600,
                                        ),
                                      ),
                                    );
                                },
                          icon: isTranslating
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.g_translate_rounded, size: 17),
                          label: Text(
                            isTranslating
                                ? 'Translating...'
                                : 'Translate to ${selectedLang.name}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.heavenBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                      if (isTranslated) ...<Widget>[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: const Key('restore_original_language_button'),
                          onPressed: () async {
                            await widget.engine.restoreOriginalPageLanguage();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text(
                            'Original',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
