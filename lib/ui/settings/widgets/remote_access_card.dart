import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/remote_access/remote_access_provider.dart';
import '../../../state/app_scope.dart';

class RemoteAccessCard extends StatefulWidget {
  const RemoteAccessCard({super.key});

  @override
  State<RemoteAccessCard> createState() => _RemoteAccessCardState();
}

class _RemoteAccessCardState extends State<RemoteAccessCard> {
  bool _isCheckingPrereqs = false;
  bool? _prereqsMet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPrerequisites();
  }

  Future<void> _checkPrerequisites() async {
    final remoteManager = AppScope.remoteAccessOf(context);
    if (remoteManager == null) return;
    if (_isCheckingPrereqs) return;

    setState(() => _isCheckingPrereqs = true);
    final met = await remoteManager.checkPrerequisites();
    if (mounted) {
      setState(() {
        _prereqsMet = met;
        _isCheckingPrereqs = false;
      });
    }
  }

  Color _getStatusColor(RemoteAccessStatus status, ColorScheme colorScheme) {
    switch (status) {
      case RemoteAccessStatus.connected:
        return Colors.green;
      case RemoteAccessStatus.starting:
      case RemoteAccessStatus.stopping:
        return Colors.amber;
      case RemoteAccessStatus.error:
        return colorScheme.error;
      case RemoteAccessStatus.disabled:
        return colorScheme.outline;
    }
  }

  String _getStatusLabel(RemoteAccessStatus status) {
    switch (status) {
      case RemoteAccessStatus.connected:
        return 'Connected (Public HTTPS Active)';
      case RemoteAccessStatus.starting:
        return 'Establishing Tunnel...';
      case RemoteAccessStatus.stopping:
        return 'Disconnecting...';
      case RemoteAccessStatus.error:
        return 'Tunnel Error';
      case RemoteAccessStatus.disabled:
        return 'Disabled (Localhost Only)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remoteManager = AppScope.remoteAccessOf(context);
    final apiServer = AppScope.apiServerOf(context);

    if (remoteManager == null) {
      return const SizedBox.shrink();
    }

    final isServerRunning = apiServer?.isRunning ?? false;
    final status = remoteManager.status;
    final isConnected = remoteManager.isConnected;
    final isTransitioning =
        remoteManager.isStarting || remoteManager.isStopping;
    final statusColor = _getStatusColor(status, theme.colorScheme);
    final publicUrl = remoteManager.publicHttpsUrl;
    final errorMessage = remoteManager.errorMessage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status chip
            Row(
              children: [
                Icon(
                  Icons.public_outlined,
                  color: isConnected ? Colors.green : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Secure Remote Access (Public HTTPS Tunnel)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getStatusLabel(status),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Allows authorized external developers to query your local GGUF model from other networks '
              'via an encrypted HTTPS tunnel. Requests still strictly require a Bearer API key.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const Divider(height: 24),

            // Provider selection & prerequisites
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tunnel Provider',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${remoteManager.providerName} — ${remoteManager.providerDescription}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_prereqsMet != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _prereqsMet!
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _prereqsMet!
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          size: 14,
                          color: _prereqsMet! ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _prereqsMet! ? 'CLI Installed' : 'CLI Missing',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _prereqsMet! ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (_prereqsMet == false) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cloudflared is not installed on this Mac',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            'Run in Terminal: brew install cloudflared',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Recheck installation',
                      onPressed: _checkPrerequisites,
                    ),
                  ],
                ),
              ),
            ],

            // Active Public HTTPS URL (shown ONLY when connected)
            if (isConnected && publicUrl != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Public HTTPS Base URL',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            publicUrl,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy HTTPS URL',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: publicUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Public HTTPS URL copied to clipboard!',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Remote endpoint: $publicUrl/v1/chat/completions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Error display
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Security Notice Banner
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hardware notice: Remote inference requests directly consume your Mac\'s CPU, '
                      'GPU memory, and battery. Remote access stops automatically when the app or local server closes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                if (!isConnected)
                  FilledButton.icon(
                    onPressed: isServerRunning && !isTransitioning
                        ? () async {
                            final success = await remoteManager
                                .startRemoteAccess();
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    remoteManager.errorMessage ??
                                        'Failed to start tunnel',
                                  ),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                            }
                          }
                        : null,
                    icon: isTransitioning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      isTransitioning
                          ? 'Starting Tunnel...'
                          : 'Start Remote Access',
                    ),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: !isTransitioning
                        ? () async {
                            await remoteManager.stopRemoteAccess();
                          }
                        : null,
                    icon: isTransitioning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop, size: 18),
                    label: Text(
                      isTransitioning ? 'Stopping...' : 'Stop Remote Access',
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                const SizedBox(width: 12),
                if (!isServerRunning)
                  Flexible(
                    child: Text(
                      'Start the local API server above before starting remote access.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
