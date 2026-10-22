import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'downloads_controller.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.downloads});

  final DownloadsController downloads;

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
            onPressed: () => _showUrlDownloadDialog(context),
            icon: const Icon(Icons.add_link_rounded),
          ),
          ListenableBuilder(
            listenable: downloads,
            builder: (BuildContext context, _) {
              final bool hasFinished = downloads.items.any(
                (DownloadEntry e) => e.isCompleted || e.isFailed,
              );
              if (!hasFinished) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Clear finished',
                onPressed: downloads.clearFinished,
                icon: const Icon(Icons.cleaning_services_outlined),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: downloads,
          builder: (BuildContext context, _) {
            final List<DownloadEntry> items = downloads.items;
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: downloads.refreshStatuses,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
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
                                Icons.download_done_rounded,
                                size: 34,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No downloads yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Files, videos, APKs, and images you download appear here with live Pause & Resume.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => _showUrlDownloadDialog(context),
                              icon: const Icon(Icons.add_link_rounded),
                              label: const Text('Download via Direct Link'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: downloads.refreshStatuses,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final DownloadEntry item = items[index];
                  return _buildDownloadCard(context, colors, isDark, item);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDownloadCard(
    BuildContext context,
    ColorScheme colors,
    bool isDark,
    DownloadEntry item,
  ) {
    final Color statusColor = switch (item.state) {
      'completed' => AppTheme.shieldEmerald,
      'failed' => AppTheme.fireCrimson,
      'paused' => AppTheme.warningAmber,
      _ => colors.primary,
    };

    final String speedSuffix = item.isRunning && item.speedBytesPerSec > 0
        ? ' • ${DownloadsController.formatBytes(item.speedBytesPerSec)}/s'
        : '';

    final String sizeText = item.totalBytes > 0
        ? '${DownloadsController.formatBytes(item.bytesDownloaded)} / ${DownloadsController.formatBytes(item.totalBytes)}$speedSuffix'
        : (item.bytesDownloaded > 0
              ? '${DownloadsController.formatBytes(item.bytesDownloaded)}$speedSuffix'
              : 'Starting download...');

    final int? pct = item.progress != null
        ? (item.progress! * 100).round()
        : null;

    final String statusLabel = switch (item.state) {
      'completed' =>
        'Completed • ${DownloadsController.formatBytes(item.totalBytes > 0 ? item.totalBytes : item.bytesDownloaded)}',
      'failed' => 'Interrupted • Tap Resume to continue',
      'paused' =>
        pct != null ? 'Paused ($pct%) • $sizeText' : 'Paused • $sizeText',
      _ => pct != null ? '$pct% • $sizeText' : sizeText,
    };

    return Material(
      color: isDark ? AppTheme.navySurface : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.isCompleted
            ? () async {
                final bool opened = await downloads.openDownload(item);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saved in your phone Downloads folder'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            : null,
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: item.url));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download link copied to clipboard'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconForFile(item.fileName, item.mimeType),
                      color: statusColor,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.fileName,
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
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pause button when running
                  if (item.isRunning)
                    IconButton(
                      tooltip: 'Pause download',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => downloads.pauseDownload(item.downloadId),
                      icon: Icon(
                        Icons.pause_circle_filled_rounded,
                        color: colors.primary,
                        size: 24,
                      ),
                    ),
                  // Resume button when paused or failed
                  if (item.isPaused || item.isFailed)
                    IconButton(
                      tooltip: 'Resume download',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          downloads.resumeDownload(item.downloadId),
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: AppTheme.shieldEmerald,
                        size: 24,
                      ),
                    ),
                  // Open button when completed
                  if (item.isCompleted)
                    IconButton(
                      tooltip: 'Open file',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        final bool opened = await downloads.openDownload(item);
                        if (!opened && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Saved in your phone Downloads folder',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    ),
                  // Cancel / Remove button always available
                  IconButton(
                    tooltip: item.isCompleted ? 'Remove from list' : 'Cancel',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => downloads.cancelAndRemove(item),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              if (item.isRunning || item.isPaused) ...<Widget>[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: item.isPaused
                        ? (item.progress ?? 0.0)
                        : item.progress,
                    minHeight: 5,
                    color: item.isPaused
                        ? AppTheme.warningAmber
                        : colors.primary,
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
    if (lower.contains('.pdf') || lower.contains('pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (lower.contains('.apk')) {
      return Icons.android_rounded;
    }
    if (lower.contains('image') ||
        lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.webp')) {
      return Icons.image_rounded;
    }
    if (lower.contains('video') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm')) {
      return Icons.movie_outlined;
    }
    if (lower.contains('audio') ||
        lower.contains('.mp3') ||
        lower.contains('.m4a')) {
      return Icons.audiotrack_rounded;
    }
    if (lower.contains('.zip') ||
        lower.contains('.rar') ||
        lower.contains('.tar') ||
        lower.contains('.7z')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _showUrlDownloadDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? entered = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Download from URL'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://example.com/file.mp4',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (String v) => Navigator.pop(dialogContext, v.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Download'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (entered != null && entered.isNotEmpty) {
      final bool ok = await downloads.startUrlDownload(url: entered);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid http:// or https:// file link'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
