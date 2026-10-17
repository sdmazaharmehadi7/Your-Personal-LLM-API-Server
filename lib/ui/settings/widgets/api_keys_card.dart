import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/api_key.dart';
import '../../../state/app_scope.dart';

class ApiKeysCard extends StatelessWidget {
  const ApiKeysCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiKeyService = AppScope.apiKeyServiceOf(context);

    if (apiKeyService == null) {
      return const SizedBox.shrink();
    }

    final keys = apiKeyService.keys;
    final activeCount = apiKeyService.activeKeysCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'API Keys & Access Control',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: activeCount > 0
                        ? Colors.green.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$activeCount active',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: activeCount > 0
                          ? Colors.green
                          : theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showCreateKeyDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Key'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Securely authenticate local HTTP clients. Requests to protected endpoints must include: '
              'Authorization: Bearer <API_KEY>. Plaintext keys are never stored on disk.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const Divider(height: 24),

            if (keys.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.key_off_outlined,
                        size: 40,
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No API keys generated yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create an API key to allow external tools to send chat requests.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: keys.length,
                separatorBuilder: (context, index) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final key = keys[index];
                  return _buildKeyItem(context, key, theme);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyItem(
    BuildContext context,
    ApiKeyMetadata key,
    ThemeData theme,
  ) {
    final isRevoked = key.isRevoked;
    final isExpired = key.isExpired;
    final isValid = key.isValid;

    final Color statusColor;
    final String statusLabel;

    if (isRevoked) {
      statusColor = theme.colorScheme.error;
      statusLabel = 'Revoked';
    } else if (isExpired) {
      statusColor = Colors.orange;
      statusLabel = 'Expired';
    } else {
      statusColor = Colors.green;
      statusLabel = 'Active';
    }

    final createdStr =
        '${key.createdAt.year}-${key.createdAt.month.toString().padLeft(2, '0')}-${key.createdAt.day.toString().padLeft(2, '0')}';
    final expiryStr = key.expiresAt != null
        ? '${key.expiresAt!.year}-${key.expiresAt!.month.toString().padLeft(2, '0')}-${key.expiresAt!.day.toString().padLeft(2, '0')}'
        : 'Never';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            isValid ? Icons.check_circle_outline : Icons.block_outlined,
            size: 20,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    key.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: isRevoked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Key: ${key.keyPrefix}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    'Created: $createdStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    'Expires: $expiryStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    'Rate: ${key.rateLimitRpm} rpm',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    'Requests: ${key.totalRequests}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isValid)
              TextButton(
                onPressed: () => _confirmRevoke(context, key),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Revoke'),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete key record',
              onPressed: () => _confirmDelete(context, key),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }

  void _showCreateKeyDialog(BuildContext context) {
    final nameController = TextEditingController();
    final rpmController = TextEditingController(text: '60');
    int expiryDays = 0; // 0 = never
    final permissions = <ApiKeyPermission>{
      ApiKeyPermission.chatCompletions,
      ApiKeyPermission.modelsList,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Create Developer API Key'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Key Description / Name',
                        hintText: 'e.g. Cursor IDE, Dev Laptop, Open WebUI',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Expiration',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: expiryDays,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 0,
                          child: Text('Never (No Expiration)'),
                        ),
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                        DropdownMenuItem(value: 90, child: Text('90 days')),
                        DropdownMenuItem(value: 365, child: Text('1 year')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => expiryDays = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rate Limit (Requests Per Minute)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: rpmController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        suffixText: 'rpm',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Permissions',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Chat Completions (/v1/chat/completions)',
                      ),
                      value: permissions.contains(
                        ApiKeyPermission.chatCompletions,
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            permissions.add(ApiKeyPermission.chatCompletions);
                          } else {
                            permissions.remove(
                              ApiKeyPermission.chatCompletions,
                            );
                          }
                        });
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('List Models (/v1/models)'),
                      value: permissions.contains(ApiKeyPermission.modelsList),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            permissions.add(ApiKeyPermission.modelsList);
                          } else {
                            permissions.remove(ApiKeyPermission.modelsList);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final rpm = int.tryParse(rpmController.text.trim()) ?? 60;
                  final expiresAt = expiryDays > 0
                      ? DateTime.now().add(Duration(days: expiryDays))
                      : null;

                  Navigator.pop(ctx);

                  final apiKeyService = AppScope.apiKeyServiceOf(context);
                  if (apiKeyService == null) return;

                  final result = await apiKeyService.createKey(
                    name: name,
                    expiresAt: expiresAt,
                    permissions: permissions,
                    rateLimitRpm: rpm,
                  );

                  if (context.mounted) {
                    _showSecretKeyDialog(context, result);
                  }
                },
                child: const Text('Generate Key'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSecretKeyDialog(
    BuildContext context,
    GeneratedApiKeyResult result,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: const Icon(Icons.security, size: 36, color: Colors.amber),
          title: const Text('Save Your Secret API Key'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'For security reasons, this secret key will NEVER be displayed again. '
                          'Copy and store it in a secure location now.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'API Key (${result.metadata.name})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          result.plaintextSecret,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy to Clipboard',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: result.plaintextSecret),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('API Key copied to clipboard!'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I Have Saved My Key'),
            ),
          ],
        );
      },
    );
  }

  void _confirmRevoke(BuildContext context, ApiKeyMetadata key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke "${key.name}"?'),
        content: Text(
          'Any application using this key (${key.keyPrefix}) will immediately receive 401 Unauthorized errors. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              AppScope.apiKeyServiceOf(context)?.revokeKey(key.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Key "${key.name}" revoked.')),
              );
            },
            child: const Text('Revoke Key'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ApiKeyMetadata key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${key.name}"?'),
        content: const Text(
          'Permanently remove this API key record and all usage metrics. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              AppScope.apiKeyServiceOf(context)?.deleteKey(key.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Key "${key.name}" deleted.')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
