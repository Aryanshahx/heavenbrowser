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
    required this.onOpenCleanReader,
    required this.onClearSiteData,
  });

  final BrowserEngine engine;
  final BrowserSettingsController settings;
  final Future<void> Function() onOpenCleanReader;
  final VoidCallback onClearSiteData;

  @override
  State<TranslateReaderSheet> createState() => _TranslateReaderSheetState();
}

class _TranslateReaderSheetState extends State<TranslateReaderSheet> {
  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String host = OmniboxParser.cleanDomain(widget.engine.currentUrl);
    final bool isHttps =
        widget.engine.currentUrl?.startsWith('https://') ?? false;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.settings, widget.engine]),
      builder: (BuildContext context, _) {
        final String selectedLangCode = widget.settings.translateTargetLang;
        final TranslateLanguage selectedLang =
            PageTranslateReaderService.languageByCode(selectedLangCode);
        final bool isTranslated = widget.engine.isPageTranslated;
        final bool isTranslating = widget.engine.isTranslatingPage;

        return SafeArea(
          child: SingleChildScrollView(
            key: const Key('translate_reader_sheet'),
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
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
                        color:
                            (isHttps ? AppTheme.shieldEmerald : colors.error)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        isHttps
                            ? Icons.lock_rounded
                            : Icons.info_outline_rounded,
                        color: isHttps ? AppTheme.shieldEmerald : colors.error,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            host.isEmpty ? 'Translate & Reader' : host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isHttps
                                ? 'Encrypted HTTPS • Instant Translate & Reader'
                                : 'Instant Page Translate & Clean Reader Mode',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isHttps
                                  ? AppTheme.shieldEmerald
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Instant Page Translate Card
                Material(
                  color: colors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isTranslated
                          ? AppTheme.heavenAccent.withValues(alpha: 0.55)
                          : colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.translate_rounded,
                              size: 20,
                              color: AppTheme.heavenAccent,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Instant Page Translate',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (isTranslated)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.shieldEmerald.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Translated (${widget.engine.translatedLangCode?.toUpperCase() ?? selectedLang.code.toUpperCase()})',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.shieldEmerald,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Translates live webpages & search results in-place without reloading.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 11),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: PageTranslateReaderService
                                .supportedLanguages
                                .length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                label: Text(
                                  lang.name == lang.nativeLabel
                                      ? lang.name
                                      : '${lang.name} • ${lang.nativeLabel}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : colors.onSurface,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: AppTheme.heavenBlue,
                                backgroundColor: colors.surface,
                                showCheckmark: false,
                                onSelected: (_) {
                                  widget.settings.setTranslateTargetLang(
                                    lang.code,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('translate_page_now_button'),
                                onPressed:
                                    (!widget.engine.isShowingWebPage ||
                                        isTranslating)
                                    ? null
                                    : () async {
                                        final ScaffoldMessengerState messenger =
                                            ScaffoldMessenger.of(context);
                                        final bool ok = await widget.engine
                                            .translateCurrentPage(
                                              selectedLang.code,
                                            );
                                        if (!mounted) return;
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? 'Page translated to ${selectedLang.name}'
                                                  : 'Unable to translate this page right now',
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
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
                                    : const Icon(
                                        Icons.g_translate_rounded,
                                        size: 17,
                                      ),
                                label: Text(
                                  isTranslating
                                      ? 'Translating...'
                                      : 'Translate to ${selectedLang.name}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.heavenBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            if (isTranslated) ...<Widget>[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                key: const Key(
                                  'restore_original_language_button',
                                ),
                                onPressed: () async {
                                  await widget.engine
                                      .restoreOriginalPageLanguage();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Original',
                                  style: TextStyle(
                                    fontSize: 12,
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

                const SizedBox(height: 12),

                // 2. Clean Reader Mode Card
                Material(
                  color: colors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: const Key('open_clean_reader_button'),
                    enabled: widget.engine.isShowingWebPage,
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.heavenAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        color: AppTheme.heavenAccent,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Clean Reader Mode',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Distraction-free article view with Midnight, Sepia & font controls',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: !widget.engine.isShowingWebPage
                        ? null
                        : () async {
                            Navigator.of(context).pop();
                            await widget.onOpenCleanReader();
                          },
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Compact Page View Controls (Desktop Site + Text Zoom + Clear Site Cookies)
                Material(
                  color: colors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: <Widget>[
                      SwitchListTile.adaptive(
                        dense: true,
                        secondary: const Icon(
                          Icons.desktop_windows_outlined,
                          size: 20,
                        ),
                        title: const Text(
                          'Desktop Site',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        value: widget.settings.desktopMode,
                        onChanged: (bool v) =>
                            widget.engine.setDesktopModeAndReload(v),
                      ),
                      Divider(
                        height: 1,
                        color: colors.outlineVariant.withValues(alpha: 0.3),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.format_size_rounded, size: 19),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Page Text Size',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_rounded, size: 18),
                              onPressed: () =>
                                  widget.settings.setTextScalePercent(
                                    widget.settings.textScalePercent - 10,
                                  ),
                            ),
                            Text(
                              '${widget.settings.textScalePercent}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              onPressed: () =>
                                  widget.settings.setTextScalePercent(
                                    widget.settings.textScalePercent + 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (host.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cookie_outlined, size: 17),
                      label: Text('Clear Cookies & Site Data for $host'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onClearSiteData();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
