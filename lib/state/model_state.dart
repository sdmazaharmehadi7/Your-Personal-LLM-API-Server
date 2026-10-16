import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_model.dart';
import '../services/inference_service.dart';
import '../services/model_download_service.dart';
import '../services/rag/embedding_service.dart';
import '../services/storage_service.dart';

class ModelState extends ChangeNotifier {
  final IInferenceService _inferenceService;
  final IModelDownloadService _downloadService;
  final IStorageService? _storageService;
  final String? _customModelsDirectory;
  final IEmbeddingService? embeddingService;
  String? _resolvedModelsDirectory;
  StreamSubscription<ModelDownloadProgress>? _downloadSubscription;

  final List<LocalModel> _catalogModels = [
    const LocalModel(
      id: 'all-minilm-l6-v2-q4',
      name: 'all-MiniLM-L6-v2 (Embedding)',
      family: 'MiniLM',
      parameterSize: '22M',
      quantization: 'Q4_K_M',
      diskSizeGb: 0.023,
      estimatedRamGb: 0.05,
      minRamGb: 0.2,
      publisher: 'Sentence Transformers',
      license: 'Apache 2.0',
      description:
          'Compact 384-dimensional neural embedding model for semantic search and local RAG. Runs offline via llamadart on Metal and ARM64.',
      filename: 'all-MiniLM-L6-v2-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/second-state/All-MiniLM-L6-v2-Embedding-GGUF/resolve/main/all-MiniLM-L6-v2-Q4_K_M.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
      isEmbeddingModel: true,
    ),
    const LocalModel(
      id: 'smollm2-135m-q4',
      name: 'SmolLM2 135M Instruct',
      family: 'SmolLM',
      parameterSize: '135M',
      quantization: 'Q4_K_M',
      diskSizeGb: 0.09,
      estimatedRamGb: 0.25,
      minRamGb: 0.5,
      publisher: 'HuggingFaceTB',
      license: 'Apache 2.0',
      description: 'Ultra-compact test model. Ideal for instant smoke testing and low-memory validation on any Android phone.',
      filename: 'smollm2-135m-instruct-q4_k_m.gguf',
      downloadUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q4_k_m.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
    const LocalModel(
      id: 'qwen-2.5-0.5b-q4',
      name: 'Qwen 2.5 0.5B Instruct',
      family: 'Qwen',
      parameterSize: '0.5B',
      quantization: 'Q4_K_M',
      diskSizeGb: 0.39,
      estimatedRamGb: 0.7,
      minRamGb: 1.0,
      publisher: 'Qwen',
      license: 'Apache 2.0',
      description: 'Lightweight high-efficiency model with strong multilingual understanding and low resource footprint.',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
    const LocalModel(
      id: 'qwen-2.5-1.5b-q4',
      name: 'Qwen 2.5 1.5B Instruct',
      family: 'Qwen',
      parameterSize: '1.5B',
      quantization: 'Q4_K_M',
      diskSizeGb: 1.1,
      estimatedRamGb: 1.8,
      minRamGb: 2.5,
      publisher: 'Qwen',
      license: 'Apache 2.0',
      description: 'Balanced reasoning and coding assistance model. Fast generation with rich multi-turn conversational quality.',
      filename: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
    const LocalModel(
      id: 'llama-3.2-1b-q4',
      name: 'Llama 3.2 1B Instruct',
      family: 'Llama',
      parameterSize: '1B',
      quantization: 'Q4_K_M',
      diskSizeGb: 0.8,
      estimatedRamGb: 1.4,
      minRamGb: 2.0,
      publisher: 'Meta / bartowski',
      license: 'Llama 3.2 Community',
      description: 'Ultra-compact mobile-friendly model by Meta optimized for on-device reasoning and conversational tasks.',
      filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
    const LocalModel(
      id: 'gemma-2-2b-it-abliterated-q4',
      name: 'Gemma 2 2B IT Abliterated',
      family: 'Gemma',
      parameterSize: '2B',
      quantization: 'Q4_K_M',
      diskSizeGb: 1.6,
      estimatedRamGb: 2.5,
      minRamGb: 4.0,
      publisher: 'bartowski',
      license: 'Gemma Terms / Open Weights',
      description: 'Uncensored local model with refusal mechanisms neutralized. Strong reasoning and creative assistance.',
      filename: 'gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      downloadUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-abliterated-GGUF/resolve/main/gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
    const LocalModel(
      id: 'llama-3.2-3b-q4',
      name: 'Llama 3.2 3B Instruct',
      family: 'Llama',
      parameterSize: '3B',
      quantization: 'Q4_K_M',
      diskSizeGb: 2.0,
      estimatedRamGb: 3.2,
      minRamGb: 4.5,
      publisher: 'Meta / bartowski',
      license: 'Llama 3.2 Community',
      description: 'Strongest compact model for high-tier phones and desktop. Enhanced instruction following and structured coding.',
      filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      downloadStatus: ModelDownloadStatus.notDownloaded,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.catalog,
    ),
  ];

  final List<LocalModel> _models = [];
  LocalModel? _activeModel;
  bool _isLoading = false;
  String? _loadingMessage;
  String? _errorMessage;
  bool _isImporting = false;
  double _importProgress = 0.0;
  String? _importingFilename;
  String _searchQuery = '';

  ModelState({
    IInferenceService? inferenceService,
    IModelDownloadService? downloadService,
    this._storageService,
    String? modelsDirectory,
    this.embeddingService,
  }) : _inferenceService = inferenceService ?? LocalInferenceService(),
       _downloadService = downloadService ?? ModelDownloadService(),
       _customModelsDirectory = modelsDirectory {
    _models.addAll(_catalogModels);
    _downloadSubscription = _downloadService.progressStream.listen(
      _onDownloadProgress,
    );
  }

  IInferenceService get inferenceService => _inferenceService;
  IModelDownloadService get downloadService => _downloadService;
  List<LocalModel> get models => List.unmodifiable(_models);
  LocalModel? get activeModel => _activeModel;
  bool get hasLoadedModel => _inferenceService.isLoaded;
  bool get isLoading => _isLoading;
  String? get loadingMessage => _loadingMessage;
  String? get errorMessage => _errorMessage;
  String? get modelsDirectory => _resolvedModelsDirectory;
  bool get isImporting => _isImporting;
  double get importProgress => _importProgress;
  String? get importingFilename => _importingFilename;
  String get searchQuery => _searchQuery;

  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }

  List<LocalModel> get filteredModels {
    if (_searchQuery.isEmpty) return models;
    final q = _searchQuery.toLowerCase();
    return _models.where((m) {
      return m.name.toLowerCase().contains(q) ||
          m.family.toLowerCase().contains(q) ||
          m.parameterSize.toLowerCase().contains(q) ||
          m.quantization.toLowerCase().contains(q) ||
          m.publisher.toLowerCase().contains(q) ||
          m.filename.toLowerCase().contains(q);
    }).toList();
  }

  LocalModel? get installedEmbeddingModel {
    return _models
        .where(
          (m) =>
              m.isEmbeddingModel &&
              m.downloadStatus == ModelDownloadStatus.downloaded &&
              m.localPath != null,
        )
        .firstOrNull;
  }

  bool get hasInstalledEmbeddingModel => installedEmbeddingModel != null;

  Future<void> init() async {
    if (kIsWeb) return;

    try {
      if (_customModelsDirectory != null) {
        _resolvedModelsDirectory = _customModelsDirectory;
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        _resolvedModelsDirectory = '${appDocDir.path}/sovereign_ai/models';
      }

      final dir = Directory(_resolvedModelsDirectory!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Load saved custom models from storage
      if (_storageService != null) {
        try {
          final savedCustom = await _storageService.loadCustomModels();
          for (final custom in savedCustom) {
            if (!_models.any((m) => m.id == custom.id)) {
              _models.insert(0, custom);
            }
          }
        } catch (_) {}
      }

      await refreshInstalledModels();
    } catch (_) {
      // Gracefully continue on platform limitations
    }
  }

  Future<void> _persistCustomModels() async {
    if (_storageService == null) return;
    try {
      final customModels = _models
          .where((m) => m.sourceType != ModelSourceType.catalog)
          .toList();
      await _storageService.saveCustomModels(customModels);
    } catch (_) {}
  }

  Future<void> refreshInstalledModels() async {
    if (_resolvedModelsDirectory == null) return;
    final dir = Directory(_resolvedModelsDirectory!);
    if (!await dir.exists()) return;

    final existingFiles = dir.listSync().whereType<File>().toList();

    for (int i = 0; i < _models.length; i++) {
      final model = _models[i];
      final matchingFile = existingFiles.firstWhere(
        (f) => p.basename(f.path).toLowerCase() == model.filename.toLowerCase(),
        orElse: () => File(''),
      );

      if (matchingFile.path.isNotEmpty && matchingFile.existsSync()) {
        _models[i] = model.copyWith(
          downloadStatus: ModelDownloadStatus.downloaded,
          localPath: matchingFile.path,
          downloadProgress: 1.0,
        );
      }
    }

    // Auto-discover any untracked GGUF files in directory
    for (final file in existingFiles) {
      final fileName = p.basename(file.path);
      if (!fileName.toLowerCase().endsWith('.gguf') ||
          fileName.endsWith('.part')) {
        continue;
      }

      final alreadyKnown = _models.any(
        (m) => m.filename.toLowerCase() == fileName.toLowerCase(),
      );

      if (!alreadyKnown) {
        final fileSizeBytes = file.lengthSync();
        final diskSizeGb = (fileSizeBytes / (1024 * 1024 * 1024));
        final customModel = LocalModel(
          id: 'custom_${file.path.hashCode}',
          name: fileName.replaceAll('.gguf', '').replaceAll('_', ' '),
          family: 'Imported GGUF',
          parameterSize: 'Custom',
          quantization: 'GGUF',
          diskSizeGb: double.parse(diskSizeGb.toStringAsFixed(2)),
          estimatedRamGb: double.parse((diskSizeGb * 1.3).toStringAsFixed(2)),
          minRamGb: double.parse((diskSizeGb * 1.5).toStringAsFixed(2)),
          publisher: 'Local Storage',
          description: 'Locally discovered GGUF model in app storage.',
          filename: fileName,
          downloadStatus: ModelDownloadStatus.downloaded,
          loadStatus: ModelLoadStatus.unloaded,
          downloadProgress: 1.0,
          localPath: file.path,
          sourceType: ModelSourceType.imported,
        );
        _models.insert(0, customModel);
      }
    }

    notifyListeners();
  }

  void _onDownloadProgress(ModelDownloadProgress progress) {
    final index = _models.indexWhere((m) => m.id == progress.modelId);
    if (index == -1) return;

    final current = _models[index];
    final updated = current.copyWith(
      downloadStatus: progress.status,
      downloadProgress: progress.progress,
      downloadSpeedBytesPerSec: progress.speedBytesPerSec,
      downloadedBytes: progress.downloadedBytes,
      totalBytes: progress.totalBytes,
      localPath: progress.savedFilePath ?? current.localPath,
      downloadError: progress.error,
    );

    _models[index] = updated;
    if (progress.status == ModelDownloadStatus.downloaded &&
        updated.sourceType != ModelSourceType.catalog) {
      _persistCustomModels();
    }
    notifyListeners();
  }

  Future<void> startDownload(LocalModel model) async {
    if (_resolvedModelsDirectory == null) {
      await init();
    }
    clearError();
    await _downloadService.startDownload(model, _resolvedModelsDirectory!);
  }

  Future<void> pauseDownload(String modelId) async {
    await _downloadService.pauseDownload(modelId);
  }

  Future<void> resumeDownload(LocalModel model) async {
    if (_resolvedModelsDirectory == null) {
      await init();
    }
    clearError();
    await _downloadService.resumeDownload(model, _resolvedModelsDirectory!);
  }

  Future<void> cancelDownload(String modelId) async {
    await _downloadService.cancelDownload(modelId);
    final index = _models.indexWhere((m) => m.id == modelId);
    if (index != -1 &&
        _models[index].sourceType == ModelSourceType.customUrl &&
        _models[index].downloadStatus == ModelDownloadStatus.notDownloaded) {
      // If user cancelled an uncompleted custom URL download, remove it from list
      _models.removeAt(index);
      await _persistCustomModels();
      notifyListeners();
    }
  }

  /// Option C: Download from Custom URL
  Future<bool> addAndDownloadCustomUrl({
    required String url,
    String? customName,
    String? customFilename,
  }) async {
    if (_resolvedModelsDirectory == null) {
      await init();
    }
    clearError();

    final validation = ModelDownloadService.validateAndResolveUrl(url);
    if (!validation.isValid) {
      _errorMessage = validation.error ?? 'Invalid URL.';
      notifyListeners();
      return false;
    }

    final filename = customFilename != null && customFilename.trim().isNotEmpty
        ? (customFilename.trim().endsWith('.gguf')
              ? customFilename.trim()
              : '${customFilename.trim()}.gguf')
        : validation.suggestedFilename!;

    final displayName = customName != null && customName.trim().isNotEmpty
        ? customName.trim()
        : filename.replaceAll('.gguf', '').replaceAll('_', ' ');

    final newModel = LocalModel(
      id: 'custom_url_${DateTime.now().millisecondsSinceEpoch}',
      name: displayName,
      family: 'Custom URL',
      parameterSize: 'Custom',
      quantization: 'GGUF',
      diskSizeGb: 0.0,
      estimatedRamGb: 2.0,
      minRamGb: 2.0,
      publisher: Uri.parse(validation.resolvedUrl!).host,
      license: 'External / Custom',
      description: 'Downloaded from custom URL: ${validation.resolvedUrl}',
      filename: filename,
      downloadUrl: validation.resolvedUrl,
      downloadStatus: ModelDownloadStatus.downloading,
      loadStatus: ModelLoadStatus.unloaded,
      sourceType: ModelSourceType.customUrl,
    );

    _models.insert(0, newModel);
    await _persistCustomModels();
    notifyListeners();

    await _downloadService.startDownload(newModel, _resolvedModelsDirectory!);
    return true;
  }

  /// Option B: Import Local GGUF Files
  Future<int> importLocalFiles(List<String> filePaths) async {
    if (_resolvedModelsDirectory == null) {
      await init();
    }
    clearError();

    if (filePaths.isEmpty) return 0;

    _isImporting = true;
    _importProgress = 0.0;
    notifyListeners();

    int successCount = 0;
    final dir = Directory(_resolvedModelsDirectory!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    try {
      for (int i = 0; i < filePaths.length; i++) {
        final srcPath = filePaths[i];
        final srcFile = File(srcPath);
        if (!await srcFile.exists()) continue;

        final rawFilename = p.basename(srcPath);
        if (!rawFilename.toLowerCase().endsWith('.gguf')) continue;

        _importingFilename = rawFilename;
        notifyListeners();

        // Validate GGUF magic bytes before importing
        try {
          await _downloadService.validateGgufHeader(srcFile);
        } catch (e) {
          _errorMessage =
              'File "$rawFilename" is not a valid GGUF model: ${e.toString().split('\n').first}';
          notifyListeners();
          continue;
        }

        final targetPath = p.join(_resolvedModelsDirectory!, rawFilename);
        final targetFile = File(targetPath);

        // Check if already in private storage
        if (srcFile.path != targetFile.path) {
          await _downloadService.copyFileWithProgress(
            srcPath,
            targetPath,
            onProgress: (pVal) {
              _importProgress = (i + pVal) / filePaths.length;
              notifyListeners();
            },
          );
        }

        final fileSizeBytes = targetFile.existsSync()
            ? targetFile.lengthSync()
            : 0;
        final diskSizeGb = (fileSizeBytes / (1024 * 1024 * 1024));

        final existingIdx = _models.indexWhere(
          (m) => m.filename.toLowerCase() == rawFilename.toLowerCase(),
        );

        if (existingIdx != -1) {
          _models[existingIdx] = _models[existingIdx].copyWith(
            downloadStatus: ModelDownloadStatus.downloaded,
            localPath: targetPath,
            downloadProgress: 1.0,
          );
        } else {
          final importedModel = LocalModel(
            id: 'imported_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: rawFilename.replaceAll('.gguf', '').replaceAll('_', ' '),
            family: 'Imported',
            parameterSize: 'Custom',
            quantization: 'GGUF',
            diskSizeGb: double.parse(diskSizeGb.toStringAsFixed(2)),
            estimatedRamGb: double.parse((diskSizeGb * 1.3).toStringAsFixed(2)),
            minRamGb: double.parse((diskSizeGb * 1.5).toStringAsFixed(2)),
            publisher: 'Device Storage',
            license: 'Local Import',
            description: 'Imported from device storage ($rawFilename).',
            filename: rawFilename,
            downloadStatus: ModelDownloadStatus.downloaded,
            loadStatus: ModelLoadStatus.unloaded,
            downloadProgress: 1.0,
            localPath: targetPath,
            sourceType: ModelSourceType.imported,
          );
          _models.insert(0, importedModel);
        }

        successCount++;
      }

      await _persistCustomModels();
    } catch (e) {
      _errorMessage = 'Import failed: ${e.toString().split('\n').first}';
    } finally {
      _isImporting = false;
      _importingFilename = null;
      _importProgress = 0.0;
      notifyListeners();
    }

    return successCount;
  }

  Future<void> deleteModel(LocalModel model) async {
    if (_activeModel?.id == model.id) {
      await unloadActiveModel();
    }

    if (model.isEmbeddingModel) {
      try {
        await embeddingService?.unloadModel();
      } catch (_) {}
    }

    if (model.localPath != null) {
      await _downloadService.deleteModelFile(model.localPath!);
    }

    final index = _models.indexWhere((m) => m.id == model.id);
    if (index != -1) {
      if (model.sourceType == ModelSourceType.catalog) {
        // Reset catalog item to notDownloaded
        _models[index] = model.copyWith(
          downloadStatus: ModelDownloadStatus.notDownloaded,
          clearLocalPath: true,
          downloadProgress: 0.0,
          downloadSpeedBytesPerSec: 0.0,
          downloadedBytes: 0,
          totalBytes: 0,
        );
      } else {
        // Remove imported or custom URL model
        _models.removeAt(index);
        await _persistCustomModels();
      }
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<bool> loadLocalModelFile(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
  }) async {
    if (_isLoading) return false;

    _isLoading = true;
    _loadingMessage =
        'Loading model weights and initializing native inference context...';
    _errorMessage = null;
    notifyListeners();

    try {
      await _inferenceService.loadModel(
        filePath,
        contextWindow: contextWindow,
        useGpu: useGpu,
      );

      final file = File(filePath);
      final fileName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : filePath;
      final fileSizeBytes = file.existsSync() ? file.lengthSync() : 0;
      final diskSizeGb = (fileSizeBytes / (1024 * 1024 * 1024));

      // Reset any previous model's loaded status
      for (int i = 0; i < _models.length; i++) {
        if (_models[i].loadStatus == ModelLoadStatus.loaded) {
          _models[i] = _models[i].copyWith(
            loadStatus: ModelLoadStatus.unloaded,
          );
        }
      }

      // Check if matches known presets or create new custom imported entry
      final existingIndex = _models.indexWhere(
        (m) => m.filename.toLowerCase() == fileName.toLowerCase(),
      );

      final now = DateTime.now();
      if (existingIndex != -1) {
        _activeModel = _models[existingIndex].copyWith(
          downloadStatus: ModelDownloadStatus.downloaded,
          loadStatus: ModelLoadStatus.loaded,
          localPath: filePath,
          lastUsedAt: now,
        );
        _models[existingIndex] = _activeModel!;
      } else {
        _activeModel = LocalModel(
          id: 'custom_${now.millisecondsSinceEpoch}',
          name: fileName.replaceAll('.gguf', '').replaceAll('_', ' '),
          family: 'Custom GGUF',
          parameterSize: 'Custom',
          quantization: 'GGUF',
          diskSizeGb: double.parse(diskSizeGb.toStringAsFixed(2)),
          estimatedRamGb: double.parse((diskSizeGb * 1.3).toStringAsFixed(2)),
          minRamGb: double.parse((diskSizeGb * 1.5).toStringAsFixed(2)),
          description: 'Imported local model file from device storage.',
          filename: fileName,
          downloadStatus: ModelDownloadStatus.downloaded,
          loadStatus: ModelLoadStatus.loaded,
          localPath: filePath,
          sourceType: ModelSourceType.imported,
          lastUsedAt: now,
        );
        _models.insert(0, _activeModel!);
        await _persistCustomModels();
      }

      _isLoading = false;
      _loadingMessage = null;
      notifyListeners();
      return true;
    } on InferenceException catch (e) {
      try {
        await _inferenceService.unloadModel();
      } catch (_) {}
      _errorMessage = e.message;
      _activeModel = null;
      for (int i = 0; i < _models.length; i++) {
        if (_models[i].loadStatus == ModelLoadStatus.loaded) {
          _models[i] = _models[i].copyWith(
            loadStatus: ModelLoadStatus.unloaded,
          );
        }
      }
      _isLoading = false;
      _loadingMessage = null;
      notifyListeners();
      return false;
    } catch (e) {
      try {
        await _inferenceService.unloadModel();
      } catch (_) {}
      _errorMessage =
          'An unexpected error occurred while loading the model: ${e.toString().split('\n').first}';
      _activeModel = null;
      for (int i = 0; i < _models.length; i++) {
        if (_models[i].loadStatus == ModelLoadStatus.loaded) {
          _models[i] = _models[i].copyWith(
            loadStatus: ModelLoadStatus.unloaded,
          );
        }
      }
      _isLoading = false;
      _loadingMessage = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> unloadActiveModel() async {
    if (_isLoading) return;

    _isLoading = true;
    _loadingMessage = 'Unloading model and releasing native memory buffers...';
    notifyListeners();

    try {
      await _inferenceService.unloadModel();
      for (int i = 0; i < _models.length; i++) {
        if (_models[i].loadStatus == ModelLoadStatus.loaded) {
          _models[i] = _models[i].copyWith(
            loadStatus: ModelLoadStatus.unloaded,
          );
        }
      }
      _activeModel = null;
    } finally {
      _isLoading = false;
      _loadingMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _downloadService.dispose();
    _inferenceService.dispose();
    super.dispose();
  }
}
