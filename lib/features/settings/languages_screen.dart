import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'browser_settings.dart';

class LanguagesScreen extends StatelessWidget {
  const LanguagesScreen({super.key, required this.settings});

  final BrowserSettingsController settings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Languages')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Text(
                    'Select your preferred language for Heaven UI and website Accept-Language headers.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Material(
                  color: isDark ? AppTheme.navySurface : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: <Widget>[
                      for (int i = 0;
                          i < BrowserLanguage.values.length;
                          i++) ...<Widget>[
                        if (i > 0) const Divider(height: 1),
                        Builder(
                          builder: (BuildContext context) {
                            final BrowserLanguage lang =
                                BrowserLanguage.values[i];
                            final bool selected = settings.language == lang;
                            return ListTile(
                              onTap: () => settings.setLanguage(lang),
                              leading: CircleAvatar(
                                radius: 17,
                                backgroundColor: selected
                                    ? colors.primary.withValues(alpha: 0.16)
                                    : colors.surfaceContainerHighest,
                                child: Text(
                                  lang.code.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              title: Text(
                                lang.nativeLabel,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${lang.englishLabel} (${lang.bcp47})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: colors.primary,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
