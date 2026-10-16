import 'package:flutter/material.dart';

class NoModelBanner extends StatelessWidget {
  final VoidCallback onOpenModelManager;

  const NoModelBanner({super.key, required this.onOpenModelManager});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Row(
            children: [
              Icon(
                Icons.memory_outlined,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No local GGUF model is loaded into memory.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenModelManager,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text(
                  'Model Manager',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
