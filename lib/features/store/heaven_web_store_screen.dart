import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../settings/browser_settings.dart';
import 'heaven_web_store_models.dart';

class HeavenWebStoreScreen extends StatefulWidget {
  const HeavenWebStoreScreen({
    super.key,
    required this.settings,
    this.embeddedInTab = false,
    this.topOverlayInset = 0,
    this.onExtensionChanged,
  });

  final BrowserSettingsController settings;
  final bool embeddedInTab;
  final double topOverlayInset;
  final VoidCallback? onExtensionChanged;

  @override
  State<HeavenWebStoreScreen> createState() => _HeavenWebStoreScreenState();
}

class _HeavenWebStoreScreenState extends State<HeavenWebStoreScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HeavenStoreExtension> _filteredExtensions() {
    final String q = _query.trim().toLowerCase();
    return HeavenWebStoreCatalog.top10Extensions.where((
      HeavenStoreExtension ext,
    ) {
      if (_selectedCategory == 'Installed' &&
          !widget.settings.isExtensionInstalled(ext.id)) {
        return false;
      } else if (_selectedCategory != 'All' &&
          _selectedCategory != 'Installed' &&
          ext.category != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return ext.name.toLowerCase().contains(q) ||
          ext.tagline.toLowerCase().contains(q) ||
          ext.description.toLowerCase().contains(q) ||
          ext.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final Widget body = AnimatedBuilder(
      animation: widget.settings,
      builder: (BuildContext context, _) {
        final List<HeavenStoreExtension> items = _filteredExtensions();
        final int installedCount = widget.settings.installedExtensionIds.length;
        final int activeCount = widget.settings.activeExtensionCount;

        return ListView(
          key: const Key('heaven_web_store_tab_view'),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            14,
            (widget.embeddedInTab ? widget.topOverlayInset : 0) + 12,
            14,
            28,
          ),
          children: <Widget>[
            _buildStoreHeroBanner(colors, installedCount, activeCount),
            const SizedBox(height: 12),
            TextField(
              key: const Key('web_store_search_field'),
              controller: _searchController,
              onChanged: (String v) => setState(() => _query = v),
              style: TextStyle(fontSize: 13.5, color: colors.onSurface),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search Heaven curated Chrome extensions...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: colors.primary,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: colors.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: HeavenWebStoreCatalog.categories.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final String cat = HeavenWebStoreCatalog.categories[index];
                  final bool selected = _selectedCategory == cat;
                  return ChoiceChip(
                    key: Key('web_store_cat_$cat'),
                    label: Text(
                      cat == 'Installed'
                          ? 'Installed ($installedCount)'
                          : cat == 'All'
                          ? 'All (10)'
                          : cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : colors.onSurface,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppTheme.heavenBlue,
                    backgroundColor: colors.surfaceContainerHigh,
                    showCheckmark: false,
                    side: BorderSide(
                      color: selected
                          ? AppTheme.heavenBlue
                          : colors.outlineVariant.withValues(alpha: 0.35),
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.extension_off_rounded,
                      size: 38,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No matching curated extensions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...items.map(
                (HeavenStoreExtension ext) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildExtensionCard(ext, colors),
                ),
              ),
          ],
        );
      },
    );

    if (widget.embeddedInTab) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Heaven Web Store'), centerTitle: false),
      body: body,
    );
  }

  Widget _buildStoreHeroBanner(
    ColorScheme colors,
    int installedCount,
    int activeCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0B162C), Color(0xFF172D56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.heavenAccent.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.heavenBlue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: Color(0xFF60A5FA),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Heaven Web Store',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Curated Top 10 Chrome Desktop Extensions',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93C5FD),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.shieldEmerald.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.shieldEmerald.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  '$activeCount / 10 Active',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.shieldEmerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Internally compiled for 120Hz zero-lag browsing across Google, Perplexity, DuckDuckGo, Brave, Bing & Startpage.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionCard(HeavenStoreExtension ext, ColorScheme colors) {
    final bool installed = widget.settings.isExtensionInstalled(ext.id);
    final bool enabled = widget.settings.isExtensionEnabled(ext.id);

    return Material(
      key: Key('web_store_card_${ext.id}'),
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: enabled
              ? AppTheme.heavenAccent.withValues(alpha: 0.45)
              : colors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ext.accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(ext.icon, color: ext.accentColor, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              ext.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            'v${ext.version}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ext.tagline,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ext.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.36,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ext.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (!installed)
                  FilledButton.tonalIcon(
                    key: Key('web_store_install_${ext.id}'),
                    onPressed: () async {
                      await widget.settings.installStoreExtension(ext.id);
                      widget.onExtensionChanged?.call();
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text(
                      'Install',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.heavenBlue,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                  )
                else ...<Widget>[
                  TextButton(
                    key: Key('web_store_remove_${ext.id}'),
                    onPressed: () async {
                      await widget.settings.removeStoreExtension(ext.id);
                      widget.onExtensionChanged?.call();
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: colors.error,
                    ),
                    child: const Text(
                      'Remove',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    key: Key('web_store_toggle_${ext.id}'),
                    value: enabled,
                    onChanged: (bool v) async {
                      await widget.settings.setStoreExtensionEnabled(ext.id, v);
                      widget.onExtensionChanged?.call();
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
