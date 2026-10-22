import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'downloads_controller.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.downloads});

  final DownloadsController downloads;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    widget.downloads.refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Download from URL',
            icon: const Icon(Icons.add_link_rounded),
            onPressed: () => _showNewDownloadDialog(context),
          ),
          ListenableBuilder(
            listenable: widget.downloads,
            builder: (BuildContext context, _) {
              final bool hasFinished = widget.downloads.items.any(
                (DownloadEntry e) => !e.isRunning,
              );
              if (!hasFinished) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Clear completed',
                icon: const Icon(Icons.cleaning_services_outlined, size: 20),
                onPressed: widget.downloads.clearFinishedDownloads,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.downloads,
          builder: (BuildContext context, _) {
            final List<DownloadEntry> items = widget.downloads.items;
            if (items.isEmpty) {
              return _buildEmptyState(context, colors);
            }

            return RefreshIndicator(
              onRefresh: widget.downloads.refreshStatuses,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  return _buildDownloadCard(
                    context,
                    colors,
                    isDark,
                    items[index],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.download_for_offline_outlined,
                size: 36,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No downloads yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Files, PDFs, APKs, videos, and images you download in Heaven Browser appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _showNewDownloadDialog(context),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Download Direct Link'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    DownloadEntry entry,
  ) {
    final IconData fileIcon = _iconForFile(entry.fileName, entry.mimeType);
    final Color statusColor = switch (entry.state) {
      'completed' => AppTheme.shieldEmerald,
      'failed' => AppTheme.fireCrimson,
      'paused' => AppTheme.warningAmber,
      _ => colors.primary,
    };

    final String statusLabel = switch (entry.state) {
      'completed' =>
        entry.totalBytes > 0
            ? 'Completed • ${DownloadsController.formatBytes(entry.totalBytes)}'
            : 'Completed • Tap to open',
      'failed' => 'Download failed',
      'paused' => 'Paused',
      _ =>
        entry.totalBytes > 0
            ? '${DownloadsController.formatBytes(entry.bytesDownloaded)} / '
                  '${DownloadsController.formatBytes(entry.totalBytes)} '
                  '(${((entry.progress ?? 0) * 100).round()}%)'
            : 'Downloading • ${DownloadsController.formatBytes(entry.bytesDownloaded)}',
    };

    return Material(
      color: isDark ? const Color(0xFF130C26) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: entry.isCompleted
            ? () async {
                final bool opened = await widget.downloads.openDownload(entry);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saved in your Android Downloads folder'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(fileIcon, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy download link',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: entry.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Download URL copied'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: entry.isRunning ? 'Cancel download' : 'Remove',
                    icon: Icon(
                      entry.isRunning
                          ? Icons.stop_circle_outlined
                          : Icons.delete_outline_rounded,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        widget.downloads.removeOrCancelDownload(entry),
                  ),
                ],
              ),
              if (entry.isRunning) ...<Widget>[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: entry.progress,
                    minHeight: 5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForFile(String name, String mime) {
    final String lower = '${name.toLowerCase()} ${mime.toLowerCase()}';
    if (lower.contains('.apk') || lower.contains('android.package')) {
      return Icons.android_rounded;
    }
    if (lower.contains('.pdf') || lower.contains('pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('image/')) {
      return Icons.image_rounded;
    }
    if (lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('video/')) {
      return Icons.movie_outlined;
    }
    if (lower.contains('.mp3') ||
        lower.contains('.wav') ||
        lower.contains('audio/')) {
      return Icons.audiotrack_rounded;
    }
    if (lower.contains('.zip') ||
        lower.contains('.tar') ||
        lower.contains('.gz') ||
        lower.contains('.rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _showNewDownloadDialog(BuildContext context) async {
    final TextEditingController urlCtrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Download Direct File URL'),
          content: TextField(
            controller: urlCtrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Direct file URL (https://...)',
              hintText: 'https://example.com/file.pdf',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Download'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && urlCtrl.text.trim().isNotEmpty) {
      final bool ok = await widget.downloads.startUrlDownload(
        url: urlCtrl.text.trim(),
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid http:// or https:// URL'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    urlCtrl.dispose();
  }
}
