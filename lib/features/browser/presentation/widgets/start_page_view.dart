import 'package:flutter/material.dart';
import 'package:heavenbrowser/core/constants/app_constants.dart';
import 'package:heavenbrowser/core/theme/app_theme.dart';
import 'package:heavenbrowser/core/utils/omnibox_parser.dart';
import 'package:heavenbrowser/features/settings/browser_settings.dart';

class StartPageView extends StatelessWidget {
  const StartPageView({
    super.key,
    required this.settings,
    required this.onFocusOmnibox,
    required this.onOpenUrl,
    required this.onOpenSettings,
  });

  final BrowserSettingsController settings;
  final VoidCallback onFocusOmnibox;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback onOpenSettings;

  Future<void> _showAddShortcutDialog(BuildContext context) async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController urlController = TextEditingController();

    final QuickShortcut? created = await showDialog<QuickShortcut>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Quick Shortcut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g.Proton Mail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Website URL',
                  hintText: 'e.g. mail.proton.me',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String rawTitle = titleController.text.trim();
                final String rawUrl = urlController.text.trim();
                if (rawUrl.isEmpty) {
                  return;
                }
                final Uri resolved = OmniboxParser.resolveInput(
                  rawUrl,
                  searchEngine: settings.searchEngine,
                  httpsUpgrade: settings.httpsUpgrade,
                );
                final String finalTitle = rawTitle.isNotEmpty
                    ? rawTitle
                    : OmniboxParser.formatDisplayUrl(resolved.toString());
                Navigator.of(dialogContext).pop(
                  QuickShortcut(
                    title: finalTitle,
                    url: resolved.toString(),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (created != null) {
      await settings.addShortcut(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: <Widget>[
        // Top header bar
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF6366F1), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    AppConstants.appName,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Private • Fast • Zero Tracking',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Browser Settings',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Hero Search Pill Trigger
        InkWell(
          onTap: onFocusOmnibox,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF161F33)
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colors.outlineVariant,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.search_rounded,
                  color: colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search with ${settings.searchEngine.label} or enter URL',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    settings.searchEngine.shortLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Search engine quick selector chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: SearchEngine.values.map((SearchEngine engine) {
              final bool selected = settings.searchEngine == engine;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(engine.label),
                  selected: selected,
                  onSelected: (_) => settings.setSearchEngine(engine),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 22),

        // Heaven Shield Privacy Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: isDark
                  ? <Color>[const Color(0xFF132238), const Color(0xFF0F1B2D)]
                  : <Color>[
                      colors.primaryContainer,
                      colors.secondaryContainer,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: settings.shieldEnabled
                  ? AppTheme.shieldEmerald.withAlpha(110)
                  : colors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    settings.shieldEnabled
                        ? Icons.verified_user_rounded
                        : Icons.gpp_maybe_outlined,
                    color: settings.shieldEnabled
                        ? AppTheme.shieldEmerald
                        : AppTheme.warningAmber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      settings.shieldEnabled
                          ? 'Heaven Shield Active'
                          : 'Heaven Shield Paused',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    value: settings.shieldEnabled,
                    onChanged: settings.setShieldEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      value: '${settings.totalTrackersBlocked}',
                      label: 'Trackers & Ads Blocked',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      value: settings.httpsUpgrade ? 'HTTPS ON' : 'Standard',
                      label: 'Smart Encryption',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Quick Dial header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Quick Launch',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAddShortcutDialog(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Site'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Quick Dial Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: settings.shortcuts.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 112,
            mainAxisExtent: 96,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (BuildContext context, int index) {
            final QuickShortcut item = settings.shortcuts[index];
            final String initial = item.title.isNotEmpty
                ? item.title.substring(0, 1).toUpperCase()
                : '?';

            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onOpenUrl(item.url),
              onLongPress: () async {
                final bool? remove = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext ctx) => AlertDialog(
                    title: Text('Remove "${item.title}"?'),
                    content: Text(item.url),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (remove == true) {
                  await settings.removeShortcutAt(index);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      child: Text(
                        initial,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (settings.shortcuts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'Tip: Long-press any shortcut to remove it.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(185),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
