import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../browser/engine/browser_engine.dart';
import 'extension_popup_sheet.dart';
import 'extensions_controller.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({
    super.key,
    required this.extensions,
    this.activeEngine,
    this.onOpenWebStoreInBrowser,
    this.onOpenUrlInNewTab,
  });

  final ExtensionsController extensions;
  final BrowserEngine? activeEngine;
  final VoidCallback? onOpenWebStoreInBrowser;
  final ValueChanged<String>? onOpenUrlInNewTab;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final TextEditingController _storeLinkController = TextEditingController();

  @override
  void dispose() {
    _storeLinkController.dispose();
    super.dispose();
  }

  Future<void> _installFromLinkOrId(String raw) async {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final String? err = await widget.extensions.installFromWebStore(trimmed);
    if (!mounted) return;
    if (err == null) {
      _storeLinkController.clear();
      await widget.activeEngine?.reloadFullPage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desktop Chrome Extension (.crx) installed & active!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _pickLocalCrxFile() async {
    final String? err = await widget.extensions.pickAndInstallCrxOrZip();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
    } else {
      await widget.activeEngine?.reloadFullPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chrome Extensions',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import .crx or .zip Package',
            onPressed: widget.extensions.isInstalling ? null : _pickLocalCrxFile,
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.extensions,
          builder: (BuildContext context, _) {
            final List<InstalledChromeExtension> installed =
                widget.extensions.chromeExtensions;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: <Widget>[
                _buildWebStoreHeroCard(context, colors, isDark),
                const SizedBox(height: 18),
                if (installed.isNotEmpty) ...<Widget>[
                  Text(
                    'Installed Desktop Extensions (${installed.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final InstalledChromeExtension ext in installed) ...<Widget>[
                    _buildInstalledExtensionCard(context, colors, isDark, ext),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                ],
                const Text(
                  'Chrome Web Store — 1-Tap Install (.crx)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Downloads the official Desktop Chrome .crx bundle directly from Google Chrome Web Store and runs its manifest.json in Heaven Browser.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                for (final ChromeWebStoreCatalogItem item
                    in ExtensionsController.featuredWebStoreCatalog) ...<Widget>[
                  _buildFeaturedCatalogTile(context, colors, isDark, item),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWebStoreHeroCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.extension_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Desktop Chrome Extensions',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Supports Chrome Web Store (.crx v2/v3) & unpacked .zip MV2/MV3 bundles',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('open_chrome_web_store_button'),
                onPressed: () {
                  if (widget.onOpenWebStoreInBrowser != null) {
                    Navigator.pop(context);
                    widget.onOpenWebStoreInBrowser!();
                  } else {
                    widget.onOpenUrlInNewTab?.call(
                      ExtensionsController.chromeWebStoreHomeUrl,
                    );
                  }
                },
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('Browse Chrome Web Store'),
              ),
              OutlinedButton.icon(
                key: const Key('import_crx_file_button'),
                onPressed: widget.extensions.isInstalling
                    ? null
                    : _pickLocalCrxFile,
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Import .crx / .zip'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('webstore_url_textfield'),
                  controller: _storeLinkController,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _installFromLinkOrId,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText:
                        'Paste chromewebstore.google.com link or 32-char ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: widget.extensions.isInstalling
                    ? null
                    : () => _installFromLinkOrId(_storeLinkController.text),
                child: widget.extensions.isInstalling &&
                        widget.extensions.installingId != null
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Install'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledExtensionCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    InstalledChromeExtension ext,
  ) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: ext.enabled
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: ext.iconBytes != null
                      ? Image.memory(
                          ext.iconBytes!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.extension_rounded, color: colors.primary),
                        )
                      : Icon(Icons.extension_rounded, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              ext.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'MV${ext.manifestVersion} • v${ext.version}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ext.description.isNotEmpty)
                        Text(
                          ext.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: ext.enabled,
                  onChanged: (bool val) async {
                    await widget.extensions.toggleChromeExtension(ext.id, val);
                    await widget.activeEngine?.reloadFullPage();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (ext.hasPopup)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: ext.enabled
                        ? () => ExtensionPopupSheet.show(
                            context,
                            extension: ext,
                            activeEngine: widget.activeEngine,
                            onOpenNewTab: widget.onOpenUrlInNewTab,
                          )
                        : null,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text('Extension Popup'),
                  ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: colors.error,
                  ),
                  onPressed: () async {
                    await widget.extensions.uninstallChromeExtension(ext.id);
                    await widget.activeEngine?.reloadFullPage();
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedCatalogTile(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    ChromeWebStoreCatalogItem item,
  ) {
    final bool alreadyInstalled = widget.extensions.isInstalled(
      item.extensionId,
    );
    final bool installingThis =
        widget.extensions.isInstalling &&
        widget.extensions.installingId == item.extensionId;

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.extension_outlined, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (alreadyInstalled)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.shieldEmerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Added',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.shieldEmerald,
                  ),
                ),
              )
            else
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.extensions.isInstalling
                    ? null
                    : () => _installFromLinkOrId(item.storeUrl),
                child: installingThis
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add .crx'),
              ),
          ],
        ),
      ),
    );
  }
}
