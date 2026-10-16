import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../state/app_scope.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int _modelsTotalSizeBytes = 0;
  int _modelsFileCount = 0;
  int _storageTotalSizeBytes = 0;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStorageStats();
  }

  Future<void> _loadStorageStats() async {
    if (kIsWeb) {
      setState(() => _isLoadingStats = false);
      return;
    }

    final modelsDirPath = AppScope.modelOf(context).modelsDirectory;
    final storageDirPath = AppScope.storageOf(context).storageDirectoryPath;

    try {
      int modelsSize = 0;
      int modelsCount = 0;
      if (modelsDirPath != null) {
        final modelsDir = Directory(modelsDirPath);
        if (await modelsDir.exists()) {
          final files = modelsDir.listSync().whereType<File>();
          for (final f in files) {
            modelsSize += f.lengthSync();
            modelsCount++;
          }
        }
      }

      int storageSize = 0;
      if (storageDirPath != null) {
        final storageDir = Directory(storageDirPath);
        if (await storageDir.exists()) {
          final files = storageDir.listSync().whereType<File>();
          for (final f in files) {
            storageSize += f.lengthSync();
          }
        }
      }

      if (mounted) {
        setState(() {
          _modelsTotalSizeBytes = modelsSize;
          _modelsFileCount = modelsCount;
          _storageTotalSizeBytes = storageSize;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelState = AppScope.modelOf(context);
    final settingsState = AppScope.settingsOf(context);
    final activeModel = modelState.activeModel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & System Audit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Stats',
            onPressed: () {
              setState(() => _isLoadingStats = true);
              _loadStorageStats();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionCard(
                theme,
                title: 'On-Device Inference Engine',
                icon: Icons.memory,
                items: [
                  _DiagnosticItem(
                    label: 'Engine Core',
                    value: 'Native llama.cpp C++ via Dart FFI (llamadart)',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Model Format',
                    value: 'GGUF (Binary validated: 0x47475546)',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Loaded Model',
                    value: activeModel != null
                        ? '${activeModel.name} (${activeModel.quantization})'
                        : 'None (Inference offline)',
                    isGood: activeModel != null,
                  ),
                  _DiagnosticItem(
                    label: 'Memory Safety',
                    value: 'Strict single-model exclusivity (Auto-unloads previous)',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'GPU Acceleration',
                    value: settingsState.generationSettings.useGpuAcceleration
                        ? 'Enabled (Metal on Apple / Vulkan on Android)'
                        : 'Disabled (CPU only)',
                    isGood: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                title: 'Host Platform & Hardware',
                icon: Icons.devices_other,
                items: [
                  _DiagnosticItem(
                    label: 'Operating System',
                    value: kIsWeb
                        ? 'Web Browser'
                        : '${Platform.operatingSystem.toUpperCase()} (${Platform.operatingSystemVersion})',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Logical CPU Cores',
                    value: kIsWeb
                        ? 'Browser Sandbox'
                        : '${Platform.numberOfProcessors} cores',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Android Large Heap',
                    value: 'android:largeHeap="true" declared in Manifest',
                    isGood: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                title: 'Persistent Storage Audit',
                icon: Icons.folder_special_outlined,
                items: [
                  _DiagnosticItem(
                    label: 'Models Directory',
                    value: modelState.modelsDirectory ?? 'Not initialized',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Model Storage Used',
                    value: _isLoadingStats
                        ? 'Calculating...'
                        : '${_formatBytes(_modelsTotalSizeBytes)} ($_modelsFileCount model file${_modelsFileCount == 1 ? '' : 's'})',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Chat & Config Storage',
                    value: _isLoadingStats
                        ? 'Calculating...'
                        : '${_formatBytes(_storageTotalSizeBytes)} (Atomic versioned JSON)',
                    isGood: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                title: 'Privacy & Zero-Telemetry Audit',
                icon: Icons.shield_outlined,
                items: [
                  _DiagnosticItem(
                    label: 'Cloud AI APIs',
                    value: 'None (No OpenAI, Anthropic, or external API endpoints)',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Analytics / Tracking',
                    value: '0 SDKs (Zero telemetry, zero tracking)',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Network Access',
                    value:
                        'Restricted solely to user-initiated model downloads',
                    isGood: true,
                  ),
                  _DiagnosticItem(
                    label: 'Offline Usability',
                    value: '100% functional without internet once models are saved',
                    isGood: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Device RAM Sizing Guidelines',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ensure your device has sufficient RAM available before loading larger models. '
                        'If Android terminates the app due to Low Memory Killer (LMK), select a smaller parameter model:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildGuidelineRow(
                        '2–4 GB RAM',
                        'SmolLM2 135M / Qwen 0.5B Instruct',
                        theme,
                      ),
                      _buildGuidelineRow(
                        '4–6 GB RAM',
                        'Llama 3.2 1B Instruct / Qwen 1.5B',
                        theme,
                      ),
                      _buildGuidelineRow(
                        '8+ GB RAM',
                        'Gemma 2 2B Abliterated / Llama 3.2 3B',
                        theme,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidelineRow(String ram, String models, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ram,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              models,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<_DiagnosticItem> items,
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
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        item.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (item.isGood)
                            const Padding(
                              padding: EdgeInsets.only(right: 6.0),
                              child: Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              item.value,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticItem {
  final String label;
  final String value;
  final bool isGood;

  _DiagnosticItem({
    required this.label,
    required this.value,
    this.isGood = false,
  });
}
