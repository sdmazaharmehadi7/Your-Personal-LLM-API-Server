import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/local_model.dart';
import '../../services/model_download_service.dart';
import '../../state/app_scope.dart';
import 'widgets/model_card.dart';

class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  int _selectedTab = 0; // 0: Catalog, 1: My Models, 2: Downloads
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importLocalFiles(BuildContext context) async {
    final theme = Theme.of(context);
    final modelState = AppScope.modelOf(context);

    if (modelState.isLoading || modelState.isImporting) return;

    if (kIsWeb) {
      _showDialog(
        context,
        title: 'Platform Unsupported',
        message:
            'GGUF local model execution and file imports are not supported in web browser environments. '
            'Please run the mobile (Android) or desktop app.',
      );
      return;
    }

    try {
      final result = await FilePicker.pickFiles(type: FileType.any);

      if (result.isEmpty) return;

      final validPaths = result
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.toLowerCase().endsWith('.gguf'))
          .toList();

      if (validPaths.isEmpty) {
        if (context.mounted) {
          _showDialog(
            context,
            title: 'No Valid .gguf Files',
            message:
                'None of the selected files end with the .gguf extension. '
                'Please select valid quantized GGUF model files.',
          );
        }
        return;
      }

      final count = await modelState.importLocalFiles(validPaths);

      if (context.mounted && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: theme.colorScheme.primaryContainer,
            content: Text(
              'Successfully imported $count GGUF model${count > 1 ? 's' : ''} to app storage.',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
        );
        setState(() {
          _selectedTab = 1; // Switch to "My Models" tab
        });
      }
    } catch (e) {
      if (context.mounted) {
        _showDialog(
          context,
          title: 'Import Failed',
          message: 'An error occurred during file import: $e',
        );
      }
    }
  }

  void _showCustomUrlDialog(BuildContext context) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    String? validationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);

            void validateLive(String val) {
              final res = ModelDownloadService.validateAndResolveUrl(val);
              setModalState(() {
                if (val.trim().isEmpty) {
                  validationError = null;
                } else if (!res.isValid) {
                  validationError = res.error;
                } else {
                  validationError = null;
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Download from URL',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Paste a direct HTTPS download link to any compatible .gguf file. '
                      'For Hugging Face, copy the download link from the "Files" tab (ending in .gguf).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: InputDecoration(
                        labelText: 'Direct GGUF URL *',
                        hintText: 'https://huggingface.co/.../model-q4.gguf',
                        errorText: validationError,
                        prefixIcon: const Icon(Icons.cloud_download_outlined),
                      ),
                      onChanged: validateLive,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Custom Model Name (Optional)',
                        hintText: 'e.g. My Fine-tuned Model',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Start Download'),
                          onPressed: () async {
                            final url = urlController.text.trim();
                            final validation =
                                ModelDownloadService.validateAndResolveUrl(url);

                            if (!validation.isValid) {
                              setModalState(() {
                                validationError = validation.error;
                              });
                              return;
                            }

                            Navigator.pop(ctx);
                            final modelState = AppScope.modelOf(context);
                            final success = await modelState
                                .addAndDownloadCustomUrl(
                                  url: url,
                                  customName:
                                      nameController.text.trim().isNotEmpty
                                      ? nameController.text.trim()
                                      : null,
                                );

                            if (success && context.mounted) {
                              setState(() {
                                _selectedTab = 2; // Switch to "Downloads" tab
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  content: Text(
                                    'Download started for custom GGUF model.',
                                    style: TextStyle(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelState = AppScope.modelOf(context);
    final settingsState = AppScope.settingsOf(context);
    final activeModel = modelState.activeModel;

    // Filter models according to selected tab and search query
    final allFiltered = modelState.filteredModels;
    final List<LocalModel> tabModels;
    if (_selectedTab == 0) {
      // Live Catalog
      tabModels = allFiltered
          .where((m) => m.sourceType == ModelSourceType.catalog)
          .toList();
    } else if (_selectedTab == 1) {
      // My Models (Downloaded & Imported)
      tabModels = allFiltered
          .where((m) => m.downloadStatus == ModelDownloadStatus.downloaded)
          .toList();
    } else {
      // Active Downloads / In-flight
      tabModels = allFiltered
          .where(
            (m) =>
                m.downloadStatus == ModelDownloadStatus.downloading ||
                m.downloadStatus == ModelDownloadStatus.paused ||
                m.downloadStatus == ModelDownloadStatus.error,
          )
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import Local GGUF Files',
            onPressed: modelState.isLoading || modelState.isImporting
                ? null
                : () => _importLocalFiles(context),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Download from URL',
            onPressed: () => _showCustomUrlDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Search Bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText:
                      'Search models by name, family, quant, or publisher...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            modelState.setSearchQuery('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (val) {
                  modelState.setSearchQuery(val);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),

              // Quick Action Bar: Import & Custom URL Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: modelState.isLoading || modelState.isImporting
                          ? null
                          : () => _importLocalFiles(context),
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Import .gguf'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showCustomUrlDialog(context),
                      icon: const Icon(Icons.add_link, size: 16),
                      label: const Text('Download from URL'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Segmented Tab Filter: Catalog, My Models, Downloads
              SegmentedButton<int>(
                segments: [
                  const ButtonSegment<int>(
                    value: 0,
                    label: Text('Catalog'),
                    icon: Icon(Icons.storefront_outlined, size: 16),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text(
                      'My Models (${modelState.models.where((m) => m.downloadStatus == ModelDownloadStatus.downloaded).length})',
                    ),
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    label: Text(
                      'Downloads (${modelState.models.where((m) => m.downloadStatus == ModelDownloadStatus.downloading || m.downloadStatus == ModelDownloadStatus.paused).length})',
                    ),
                    icon: const Icon(Icons.downloading, size: 16),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (Set<int> newSelection) {
                  setState(() {
                    _selectedTab = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Import Progress Indicator
              if (modelState.isImporting) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Importing: ${modelState.importingFilename ?? 'model file'}...',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${(modelState.importProgress * 100).toStringAsFixed(0)}%',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: modelState.importProgress > 0
                            ? modelState.importProgress
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],

              // Engine Loading Progress Indicator
              if (modelState.isLoading) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          modelState.loadingMessage ?? 'Processing model...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Error Message Banner
              if (modelState.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          modelState.errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            height: 1.4,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: modelState.clearError,
                      ),
                    ],
                  ),
                ),
              ],

              // Active Model in RAM Banner
              if (activeModel != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF1E2E28)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10A37A).withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10A37A)
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.memory,
                          color: Color(0xFF10A37A),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active in RAM: ${activeModel.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Context: ${settingsState.generationSettings.contextWindow} tokens • File: ${activeModel.filename}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: modelState.isLoading
                            ? null
                            : () => modelState.unloadActiveModel(),
                        child: const Text('Unload'),
                      ),
                    ],
                  ),
                ),
              ],

              // Model List or Empty State
              if (tabModels.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 20,
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          _selectedTab == 0
                              ? Icons.search_off
                              : (_selectedTab == 1
                                    ? Icons.inventory_2_outlined
                                    : Icons.cloud_done_outlined),
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedTab == 0
                              ? 'No models match "${modelState.searchQuery}"'
                              : (_selectedTab == 1
                                    ? 'No Models Downloaded Yet'
                                    : 'No Active Downloads'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedTab == 0
                              ? 'Try searching with a different term or parameter size.'
                              : (_selectedTab == 1
                                    ? 'Download a model from the Catalog, import a .gguf file from device storage, or download using a custom URL.'
                                    : 'When you download a model, its live progress and speed will appear here.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        if (_selectedTab == 1) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  setState(() => _selectedTab = 0);
                                },
                                icon: const Icon(Icons.storefront, size: 16),
                                label: const Text('Browse Catalog'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => _importLocalFiles(context),
                                icon: const Icon(Icons.folder_open, size: 16),
                                label: const Text('Import File'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else ...[
                ...tabModels.map((model) {
                  return ModelCard(
                    model: model,
                    isLoading: modelState.isLoading || modelState.isImporting,
                    onPickLocal: () => _importLocalFiles(context),
                    onDownload: () => modelState.startDownload(model),
                    onPauseDownload: () => modelState.pauseDownload(model.id),
                    onResumeDownload: () => modelState.resumeDownload(model),
                    onCancelDownload: () => modelState.cancelDownload(model.id),
                    onDelete: () => modelState.deleteModel(model),
                    onLoad: model.localPath != null
                        ? () => modelState.loadLocalModelFile(
                            model.localPath!,
                            contextWindow:
                                settingsState.generationSettings.contextWindow,
                            useGpu: settingsState
                                .generationSettings
                                .useGpuAcceleration,
                          )
                        : null,
                    onUnload: () => modelState.unloadActiveModel(),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
