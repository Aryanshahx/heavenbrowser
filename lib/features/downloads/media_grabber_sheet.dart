import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/omnibox_parser.dart';
import '../browser/engine/browser_engine.dart';
import '../settings/browser_settings.dart';
import '../shield/native_shield_bridge.dart';
import 'downloads_controller.dart';
import 'downloads_screen.dart';

class MediaGrabberSheet extends StatefulWidget {
  const MediaGrabberSheet({
    super.key,
    required this.engine,
    required this.downloads,
    required this.settings,
  });

  final BrowserEngine engine;
  final DownloadsController downloads;
  final BrowserSettingsController settings;

  static Future<void> show(
    BuildContext context, {
    required BrowserEngine engine,
    required DownloadsController downloads,
    required BrowserSettingsController settings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MediaGrabberSheet(
        engine: engine,
        downloads: downloads,
        settings: settings,
      ),
    );
  }

  @override
  State<MediaGrabberSheet> createState() => _MediaGrabberSheetState();
}

class _MediaGrabberSheetState extends State<MediaGrabberSheet> {
  final TextEditingController _directStreamCtrl = TextEditingController();
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _rescan();
  }

  @override
  void dispose() {
    _directStreamCtrl.dispose();
    super.dispose();
  }

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    await widget.engine.refreshDetectedMediaStreams();
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  String _buildSuggestedFileName(DetectedMediaStream s) {
    final String baseRaw = s.label.trim().isNotEmpty
        ? s.label.trim()
        : OmniboxParser.cleanDomain(widget.engine.currentHost ?? 'media');
    final String safeBase = baseRaw
        .replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final String trimmedBase = safeBase.length > 42
        ? safeBase.substring(0, 42)
        : (safeBase.isEmpty ? 'heaven_media' : safeBase);
    final String ext = switch (s.format.toUpperCase()) {
      'MP3' => 'mp3',
      'M4A' => 'm4a',
      'AAC' => 'aac',
      'OGG' => 'ogg',
      'WAV' => 'wav',
      'WEBM' => 'webm',
      'MKV' => 'mkv',
      'HLS' => 'ts',
      _ => s.isAudio ? 'm4a' : 'mp4',
    };
    return '$trimmedBase.$ext';
  }

  Future<void> _downloadStream(DetectedMediaStream stream) async {
    final String fileName = _buildSuggestedFileName(stream);
    final String mime = stream.isAudio ? 'audio/mp4' : 'video/mp4';
    final bool ok = await widget.downloads.startUrlDownload(
      url: stream.url,
      suggestedFileName: fileName,
      mimeType: mime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Downloading offline media: $fileName'
              : 'Could not start stream download.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _downloadCustomUrl() async {
    final String url = _directStreamCtrl.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste a valid http:// or https:// media URL.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final bool ok = await widget.downloads.startUrlDownload(url: url);
    if (!mounted) return;
    if (ok) {
      _directStreamCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline media download started!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          widget.engine,
          widget.settings,
          widget.downloads,
        ]),
        builder: (BuildContext context, _) {
          final List<DetectedMediaStream> streams =
              widget.engine.detectedMediaStreams;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.80,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.video_collection_rounded,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Media Center & Stream Downloader',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Background play, Auto-PiP & offline MP4/MP3/HLS grabber',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open Downloads',
                        icon: const Icon(Icons.download_done_rounded),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  DownloadsScreen(downloads: widget.downloads),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        key: const Key('enter_pip_now_button'),
                        onPressed: () async {
                          Navigator.pop(context);
                          await NativeShieldBridge.instance
                              .enterPictureInPicture();
                        },
                        icon: const Icon(
                          Icons.picture_in_picture_alt_rounded,
                          size: 18,
                        ),
                        label: const Text('Pop-out PiP Window'),
                      ),
                      FilterChip(
                        selected: widget.settings.backgroundMediaEnabled,
                        onSelected: widget.settings.setBackgroundMediaEnabled,
                        avatar: const Icon(Icons.headphones_rounded, size: 16),
                        label: const Text('Background Play'),
                      ),
                      FilterChip(
                        selected: widget.settings.autoPipEnabled,
                        onSelected: widget.settings.setAutoPipEnabled,
                        avatar: const Icon(
                          Icons.branding_watermark_rounded,
                          size: 16,
                        ),
                        label: const Text('Auto-PiP on Home'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Detected Streams on Page (${streams.length})',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _scanning ? null : _rescan,
                        icon: const Icon(Icons.radar_rounded, size: 16),
                        label: Text(_scanning ? 'Scanning...' : 'Rescan'),
                      ),
                    ],
                  ),
                  if (streams.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.navySurface
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.4,
                              ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Start playing any video or audio on the page and tap Rescan to grab direct MP4, WebM, MP3, or HLS (.m3u8) streams for offline playback.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    for (final DetectedMediaStream s in streams)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.navySurface : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (s.isAudio
                                            ? Colors.purple
                                            : colors.primary)
                                        .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s.format.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: s.isAudio
                                      ? Colors.purpleAccent
                                      : colors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    s.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    s.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _downloadStream(s),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                              ),
                              label: const Text('Save'),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _directStreamCtrl,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: const InputDecoration(
                            hintText:
                                'Or paste direct .mp4 / .mp3 / .m3u8 URL...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _downloadCustomUrl(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _downloadCustomUrl,
                        child: const Text('Grab'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
