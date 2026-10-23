import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'extensions_controller.dart';

class ExtensionsScreen extends StatelessWidget {
  const ExtensionsScreen({
    super.key,
    required this.extensions,
    this.onExtensionsChanged,
  });

  final ExtensionsController extensions;
  final VoidCallback? onExtensionsChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Extensions',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => _showInstallSheet(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: extensions,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.extension_rounded,
                        color: colors.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${extensions.enabledCount} Active Extension${extensions.enabledCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Toggle built-in add-ons or install custom .user.js & CSS extensions.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Built-In Heaven Extensions',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final BrowserExtension ext
                    in extensions.builtInExtensions) ...<Widget>[
                  _buildExtensionTile(context, colors, isDark, ext),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Custom Userscripts & CSS',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showInstallSheet(context),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Install / Create'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (extensions.customExtensions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.navySurface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'No custom extensions installed yet. Tap "Install / Create" to import a .user.js URL or add custom JavaScript/CSS.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  for (final BrowserExtension ext
                      in extensions.customExtensions) ...<Widget>[
                    _buildExtensionTile(context, colors, isDark, ext),
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildExtensionTile(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    BrowserExtension ext,
  ) {
    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ext.enabled
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(ext.iconBadge, style: const TextStyle(fontSize: 19)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ext.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ext.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Runs on: ${ext.matchPattern == '*' ? 'All websites' : ext.matchPattern}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (!ext.isBuiltIn)
              IconButton(
                tooltip: 'Remove extension',
                onPressed: () async {
                  await extensions.removeCustomExtension(ext.id);
                  onExtensionsChanged?.call();
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            Switch(
              value: ext.enabled,
              onChanged: (bool val) async {
                await extensions.toggleExtension(ext.id, val);
                onExtensionsChanged?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInstallSheet(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController matchCtrl = TextEditingController(text: '*');
    final TextEditingController urlCtrl = TextEditingController();
    final TextEditingController cssCtrl = TextEditingController();
    final TextEditingController jsCtrl = TextEditingController();
    String? errorMsg;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Add Browser Extension',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Import from .user.js URL (optional)',
                        hintText: 'https://example.com/script.user.js',
                        suffixIcon: IconButton(
                          tooltip: 'Install URL',
                          icon: const Icon(Icons.cloud_download_rounded),
                          onPressed: () async {
                            final String? err = await extensions
                                .installUserscriptFromUrl(urlCtrl.text);
                            if (err != null) {
                              setModalState(() => errorMsg = err);
                            } else {
                              onExtensionsChanged?.call();
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Extension Name',
                        hintText: 'e.g. Custom Dark CSS',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: matchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Site Match (* for all, or domain.com)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: cssCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Custom CSS (optional)',
                        hintText: 'body { font-size: 18px !important; }',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: jsCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Custom JavaScript (optional)',
                        hintText: 'console.log("Extension loaded");',
                      ),
                    ),
                    if (errorMsg != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                          color: AppTheme.fireCrimson,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final String? err = await extensions.addCustomExtension(
                          name: nameCtrl.text,
                          matchPattern: matchCtrl.text,
                          cssCode: cssCtrl.text,
                          jsCode: jsCtrl.text,
                        );
                        if (err != null) {
                          setModalState(() => errorMsg = err);
                          return;
                        }
                        onExtensionsChanged?.call();
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Save & Enable Extension'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
