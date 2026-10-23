import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../browser/engine/browser_engine.dart';
import '../shield/native_shield_bridge.dart';
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
  final TextEditingController _storeInputController = TextEditingController();
  bool _searchingStore = false;
  String _lastSearchQuery = '';
  List<ChromeWebStoreSearchItem> _searchResults = <ChromeWebStoreSearchItem>[];

  @override
  void dispose() {
    _storeInputController.dispose();
    super.dispose();
  }

  Future<void> _handleSearchOrInstall(String raw) async {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    if (ExtensionsController.extractChromeWebStoreId(trimmed) != null) {
      await _installFromLinkOrId(trimmed);
      return;
    }

    setState(() {
      _searchingStore = true;
      _lastSearchQuery = trimmed;
    });
    final List<ChromeWebStoreSearchItem> found = await widget.extensions
        .searchWebStoreExtensions(trimmed);
    if (!mounted) return;
    setState(() {
      _searchingStore = false;
      _searchResults = found;
    });
  }

  Future<void> _installFromLinkOrId(String raw) async {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final String? err = await widget.extensions.installFromWebStore(trimmed);
    if (!mounted) return;
    if (err == null) {
      if (ExtensionsController.extractChromeWebStoreId(
            _storeInputController.text,
          ) !=
          null) {
        _storeInputController.clear();
      }
      await widget.activeEngine?.reloadFullPage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Desktop Chrome Extension (.crx) installed & running on all search engines and sites!',
            ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extension package installed and activated!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openExtensionInNewTab(
    InstalledChromeExtension ext, {
    String? customUrl,
  }) async {
    final BrowserEngine? engine = widget.activeEngine;
    await NativeShieldBridge.instance.setPopupContextTab(
      url: engine?.currentUrl ?? 'https://www.google.com',
      title: engine?.pageTitle ?? 'Heaven Tab',
      webViewId: engine?.androidWebViewId,
    );
    await NativeShieldBridge.instance.triggerChromeExtensionAction(
      id: ext.id,
      url: engine?.currentUrl ?? 'https://www.google.com',
      title: engine?.pageTitle ?? 'Heaven Tab',
    );
    await engine?.reinjectActiveExtensions();
    final String targetUrl = customUrl ?? ext.effectiveLaunchUrl;
    if (mounted) {
      Navigator.of(context).pop();
    }
    widget.onOpenUrlInNewTab?.call(targetUrl);
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
            onPressed: widget.extensions.isInstalling
                ? null
                : _pickLocalCrxFile,
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
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: <Widget>[
                _buildWebStoreHeroCard(context, colors, isDark),
                const SizedBox(height: 14),
                if (_searchingStore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_lastSearchQuery.isNotEmpty) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Web Store Results for "$_lastSearchQuery" (${_searchResults.length})',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _lastSearchQuery = '';
                            _searchResults = <ChromeWebStoreSearchItem>[];
                            _storeInputController.clear();
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  if (_searchResults.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No direct matches found. Tap "Chrome Web Store" above to browse all extensions in Desktop View.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final ChromeWebStoreSearchItem item
                        in _searchResults) ...<Widget>[
                      _buildSearchResultTile(context, colors, isDark, item),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 10),
                ],
                if (installed.isNotEmpty) ...<Widget>[
                  Text(
                    'Installed Extensions (${installed.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final InstalledChromeExtension ext
                      in installed) ...<Widget>[
                    _buildInstalledExtensionCard(context, colors, isDark, ext),
                    const SizedBox(height: 10),
                  ],
                ] else if (_lastSearchQuery.isEmpty) ...<Widget>[
                  _buildCleanEmptyState(colors, isDark),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCleanEmptyState(ColorScheme colors, bool isDark) {
    return Container(
      key: const Key('extensions_empty_state'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.extension_off_rounded,
            size: 38,
            color: colors.primary.withValues(alpha: 0.78),
          ),
          const SizedBox(height: 10),
          const Text(
            'No Extensions Installed Yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Open the Chrome Web Store in Desktop mode, search above, paste an extension link, or import a .crx / .zip file. Installed extensions run across Google, DuckDuckGo, Brave, Bing, and every website.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStoreHeroCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.navySurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.extension_rounded,
                  size: 20,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Desktop Chrome Extensions',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'MV2 & MV3 background workers + content scripts on any engine',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('open_chrome_web_store_button'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
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
                icon: const Icon(Icons.desktop_windows_rounded, size: 16),
                label: const Text(
                  'Chrome Web Store',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('import_crx_file_button'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: widget.extensions.isInstalling
                    ? null
                    : _pickLocalCrxFile,
                icon: const Icon(Icons.folder_zip_outlined, size: 16),
                label: const Text(
                  'Import .crx / .zip',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('webstore_url_textfield'),
                  controller: _storeInputController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _handleSearchOrInstall,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search Web Store or paste extension link / ID',
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: (widget.extensions.isInstalling || _searchingStore)
                    ? null
                    : () => _handleSearchOrInstall(_storeInputController.text),
                child:
                    (widget.extensions.isInstalling &&
                            widget.extensions.installingId != null) ||
                        _searchingStore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Go'),
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('installed_extension_card_${ext.id}'),
        onTap: ext.enabled ? () => _openExtensionInNewTab(ext) : null,
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
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
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
                            errorBuilder: (_, _, _) => Icon(
                              Icons.extension_rounded,
                              color: colors.primary,
                            ),
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
                      await widget.extensions.toggleChromeExtension(
                        ext.id,
                        val,
                      );
                      await widget.activeEngine?.reloadFullPage();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: ext.enabled
                        ? () => _openExtensionInNewTab(ext)
                        : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open in New Tab'),
                  ),
                  if (ext.hasOptions && ext.optionsUrl != ext.popupUrl)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: ext.enabled
                          ? () => _openExtensionInNewTab(
                              ext,
                              customUrl: ext.optionsUrl,
                            )
                          : null,
                      icon: const Icon(Icons.tune_rounded, size: 15),
                      label: const Text('Options'),
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
      ),
    );
  }

  Widget _buildSearchResultTile(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    ChromeWebStoreSearchItem item,
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
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
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
