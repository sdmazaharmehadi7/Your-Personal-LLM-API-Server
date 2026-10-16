import 'package:flutter/material.dart';

import '../../../models/local_model.dart';
import '../../common/status_badge.dart';

class ModelCard extends StatelessWidget {
  final LocalModel model;
  final VoidCallback? onLoad;
  final VoidCallback? onUnload;
  final VoidCallback? onPickLocal;
  final VoidCallback? onDownload;
  final VoidCallback? onPauseDownload;
  final VoidCallback? onResumeDownload;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onDelete;
  final bool isLoading;

  const ModelCard({
    super.key,
    required this.model,
    this.onLoad,
    this.onUnload,
    this.onPickLocal,
    this.onDownload,
    this.onPauseDownload,
    this.onResumeDownload,
    this.onCancelDownload,
    this.onDelete,
    this.isLoading = false,
  });

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatSize(int downloaded, int total) {
    final downMb = downloaded / (1024 * 1024);
    if (total > 0) {
      final totalMb = total / (1024 * 1024);
      if (totalMb >= 1024) {
        return '${(downMb / 1024).toStringAsFixed(2)} / ${(totalMb / 1024).toStringAsFixed(2)} GB';
      }
      return '${downMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
    }
    return '${downMb.toStringAsFixed(1)} MB';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model Weights?'),
        content: Text(
          'Are you sure you want to delete the file for "${model.name}" from your local storage? '
          'You will need to download or re-import the .gguf file to use it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isDownloaded = model.downloadStatus == ModelDownloadStatus.downloaded;
    final isDownloading =
        model.downloadStatus == ModelDownloadStatus.downloading;
    final isPaused = model.downloadStatus == ModelDownloadStatus.paused;
    final isError = model.downloadStatus == ModelDownloadStatus.error;
    final isLoaded = model.loadStatus == ModelLoadStatus.loaded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark
            ? (isLoaded ? const Color(0xFF1F2E26) : const Color(0xFF202024))
            : (isLoaded ? const Color(0xFFF0FDF4) : const Color(0xFFFFFFFF)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLoaded
              ? (isDark ? const Color(0xFF10A37A) : const Color(0xFF86EFAC))
              : theme.colorScheme.outlineVariant,
          width: isLoaded ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (isLoaded) ...[
                            const SizedBox(width: 8),
                            const StatusBadge(
                              icon: Icons.check_circle_rounded,
                              label: 'Loaded in RAM',
                              color: Color(0xFF10A37A),
                            ),
                          ],
                          if (model.isEmbeddingModel) ...[
                            const SizedBox(width: 8),
                            StatusBadge(
                              icon: Icons.hub_outlined,
                              label: 'Neural Embedding',
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(
                      label: model.quantization,
                      color: isDark
                          ? const Color(0xFFD4D4D8)
                          : const Color(0xFF3F3F46),
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(
                      label: model.license,
                      color: theme.colorScheme.outline,
                      isOutlined: true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusBadge(
                  icon: Icons.folder_zip_outlined,
                  label: '${model.diskSizeGb} GB Disk',
                  color: theme.colorScheme.outline,
                  isOutlined: true,
                ),
                StatusBadge(
                  icon: Icons.memory_outlined,
                  label: '~${model.estimatedRamGb} GB RAM',
                  color: theme.colorScheme.outline,
                  isOutlined: true,
                ),
                StatusBadge(
                  icon: Icons.verified_user_outlined,
                  label: model.publisher,
                  color: theme.colorScheme.outline,
                  isOutlined: true,
                ),
                StatusBadge(
                  icon: Icons.speed,
                  label: 'Min ${model.minRamGb} GB',
                  color: theme.colorScheme.outline,
                  isOutlined: true,
                ),
                if (isDownloaded)
                  const StatusBadge(
                    icon: Icons.check_circle_outline,
                    label: 'Downloaded',
                    color: Color(0xFF10A37A),
                  )
                else if (isDownloading)
                  StatusBadge(
                    icon: Icons.downloading,
                    label: 'Downloading',
                    color: theme.colorScheme.primary,
                  )
                else if (isPaused)
                  const StatusBadge(
                    icon: Icons.pause_circle_outline,
                    label: 'Paused',
                    color: Colors.orange,
                  )
                else if (isError)
                  StatusBadge(
                    icon: Icons.error_outline,
                    label: 'Failed',
                    color: theme.colorScheme.error,
                  )
                else
                  StatusBadge(
                    icon: Icons.cloud_download_outlined,
                    label: 'Available',
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
            if (isDownloading || isPaused) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isPaused
                            ? 'Paused (${(model.downloadProgress * 100).toStringAsFixed(1)}%)'
                            : '${(model.downloadProgress * 100).toStringAsFixed(1)}% '
                                  '(${_formatSize(model.downloadedBytes, model.totalBytes)})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isDownloading && model.downloadSpeedBytesPerSec > 0)
                        Text(
                          _formatSpeed(model.downloadSpeedBytesPerSec),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: model.downloadProgress > 0
                        ? model.downloadProgress
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ],
            if (isError && model.downloadError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.downloadError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isDownloading) ...[
                  OutlinedButton.icon(
                    onPressed: onPauseDownload,
                    icon: const Icon(Icons.pause, size: 15),
                    label: const Text('Pause'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onCancelDownload,
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else if (isPaused) ...[
                  FilledButton.tonalIcon(
                    onPressed: onResumeDownload,
                    icon: const Icon(Icons.play_arrow, size: 15),
                    label: const Text('Resume'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onCancelDownload,
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else if (isError) ...[
                  FilledButton.tonalIcon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Retry Download'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : onPickLocal,
                    icon: const Icon(Icons.folder_open, size: 15),
                    label: const Text('Import Local'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else if (!isDownloaded) ...[
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : onPickLocal,
                    icon: const Icon(Icons.file_open_outlined, size: 15),
                    label: const Text('Import .gguf'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (model.downloadUrl != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: isLoading ? null : onDownload,
                      icon: const Icon(Icons.download, size: 15),
                      label: Text(
                        'Download (${model.diskSizeGb < 0.1 ? "${(model.diskSizeGb * 1024).round()} MB" : "${model.diskSizeGb} GB"})',
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ] else ...[
                  // Downloaded / Imported
                  IconButton(
                    tooltip: 'Delete local model file',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    onPressed: isLoading ? null : () => _confirmDelete(context),
                  ),
                  const Spacer(),
                  if (model.isEmbeddingModel) ...[
                    const StatusBadge(
                      icon: Icons.check_circle_outline,
                      label: 'Ready for Neural RAG',
                      color: Color(0xFF10A37A),
                    ),
                  ] else ...[
                    if (!isLoaded) ...[
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : onPickLocal,
                        icon: const Icon(Icons.folder_open_outlined, size: 15),
                        label: const Text('Change File'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: isLoading ? null : onLoad,
                        icon: const Icon(Icons.bolt, size: 15),
                        label: const Text('Load into RAM'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                    if (isLoaded)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.errorContainer,
                          foregroundColor: theme.colorScheme.onErrorContainer,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: isLoading ? null : onUnload,
                        icon: const Icon(Icons.stop_circle_outlined, size: 15),
                        label: const Text('Unload from Memory'),
                      ),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
