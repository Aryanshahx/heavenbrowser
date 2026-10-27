import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../shield/native_shield_bridge.dart';
import '../../engine/browser_engine.dart';

/// Google Lens-style Camera & Gallery Visual Search bottom sheet.
class VisualSearchLensSheet extends StatefulWidget {
  const VisualSearchLensSheet({
    super.key,
    required this.engine,
  });

  final BrowserEngine engine;

  @override
  State<VisualSearchLensSheet> createState() => _VisualSearchLensSheetState();
}

class _VisualSearchLensSheetState extends State<VisualSearchLensSheet> {
  bool _busy = false;

  Future<void> _pickAndSearch(String source) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final Map<String, Object?> res = await NativeShieldBridge.instance
        .captureVisualSearchImage(source: source);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['cancelled'] == true) {
      return;
    }
    final String b64 = (res['base64Jpeg']?.toString() ?? '').trim();
    if (res['ok'] == true && b64.isNotEmpty) {
      Navigator.pop(context);
      await widget.engine.loadGoogleLensImageBase64(b64);
      return;
    }

    final String? err = res['error']?.toString();
    if (err != null && err.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(err),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        key: const Key('visual_search_lens_sheet'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Search with Camera',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Snap a photo or pick an image to search visually with Google Lens',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              Material(
                color: isDark ? AppTheme.navySurface : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  key: const Key('lens_take_photo_tile'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(
                    Icons.photo_camera_rounded,
                    color: colors.primary,
                  ),
                  title: const Text(
                    'Search with Camera',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Take a picture of text, objects, products, or QR codes',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickAndSearch('camera'),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: isDark ? AppTheme.navySurface : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  key: const Key('lens_pick_gallery_tile'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: colors.primary,
                  ),
                  title: const Text(
                    'Choose Image from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Search any saved screenshot or photo on your device',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickAndSearch('gallery'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
