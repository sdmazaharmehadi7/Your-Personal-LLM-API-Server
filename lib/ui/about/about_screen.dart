import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../diagnostics/diagnostics_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About Sovereign AI')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.appTagline} • v${AppConstants.appVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildCard(
                theme,
                title: 'Data Sovereignty & Privacy',
                icon: Icons.lock_outline,
                content:
                    'Sovereign AI is built on the principle that personal computing must remain private. '
                    'All language models run directly on your device CPU/GPU using quantized GGUF weights. '
                    'No prompts, context, documents, or chat history ever leave your device.',
              ),
              const SizedBox(height: 16),
              _buildCard(
                theme,
                title: 'Technical Architecture',
                icon: Icons.architecture_outlined,
                content:
                    '• Engine: Native llama.cpp C++ inference via Dart FFI (Phase 2).\n'
                    '• Format: GGUF (Quantized Q4_K_M, Q5_K_M, etc.).\n'
                    '• Concurrency: Dedicated background Dart Isolate to ensure 60/120 FPS UI streaming.\n'
                    '• UI Framework: Flutter Material 3 with adaptive layouts.',
              ),
              const SizedBox(height: 16),
              _buildCard(
                theme,
                title: 'Platform Capabilities & Limitations',
                icon: Icons.devices_other_outlined,
                content:
                    '• macOS / iOS: Full Metal GPU acceleration with unified memory.\n'
                    '• Android: 64-bit ARM (arm64-v8a) with Vulkan/OpenCL acceleration.\n'
                    '• Windows / Linux: Native AVX2/AVX-512 CPU & CUDA/Vulkan support.\n'
                    '• Web: Limited; WebAssembly/Browser sandbox restricts multi-gigabyte GGUF local execution.',
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Hardware Diagnostics & Storage Audit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required String content,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
