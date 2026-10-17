import 'dart:async';
import 'dart:io' show File, FileMode, FileSystemEntity, RandomAccessFile;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:llamadart/llamadart.dart';

import '../models/chat_message.dart';
import '../models/generation_settings.dart';
import '../models/local_model.dart';

abstract class IInferenceService {
  bool get isLoaded;
  bool get isGenerating;
  ModelLoadStatus get status;
  String? get currentModelPath;
  String? get currentModelName;

  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
  });

  Future<void> unloadModel();

  Stream<String> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  });

  Future<void> stopGeneration();

  Future<void> dispose();
}

class LocalInferenceService implements IInferenceService {
  LlamaEngine? _engine;
  String? _currentModelPath;
  String? _currentModelName;
  ModelLoadStatus _status = ModelLoadStatus.unloaded;
  bool _isGenerating = false;
  StreamSubscription<LlamaCompletionChunk>? _activeSubscription;
  StreamController<String>? _activeController;

  @override
  bool get isLoaded =>
      _engine != null &&
      (_status == ModelLoadStatus.loaded ||
          _status == ModelLoadStatus.generating);

  @override
  bool get isGenerating =>
      _isGenerating || _status == ModelLoadStatus.generating;

  @override
  ModelLoadStatus get status => _status;

  @override
  String? get currentModelPath => _currentModelPath;

  @override
  String? get currentModelName => _currentModelName;

  @override
  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
  }) async {
    if (kIsWeb) {
      _status = ModelLoadStatus.error;
      throw const InferenceException(
        'On-device GGUF inference is not supported in the web browser. '
        'Please run on native macOS, Android, Windows, or Linux.',
      );
    }

    if (_status == ModelLoadStatus.loading) {
      throw const InferenceException(
        'A model is already in the process of loading into memory.',
      );
    }

    if (_status == ModelLoadStatus.unloading) {
      throw const InferenceException(
        'A model is currently in the process of being unloaded from memory.',
      );
    }

    final trimmedPath = filePath.trim();
    if (trimmedPath.isEmpty) {
      _status = ModelLoadStatus.error;
      throw const InferenceException('No file path provided.');
    }

    // Do not load duplicate instances of the same model unintentionally
    if (isLoaded &&
        _currentModelPath == trimmedPath &&
        _status == ModelLoadStatus.loaded) {
      return;
    }

    // If currently generating, safely stop generation before switching/unloading
    if (isGenerating) {
      await stopGeneration();
    }

    if (!trimmedPath.toLowerCase().endsWith('.gguf')) {
      _status = ModelLoadStatus.error;
      throw const InferenceException(
        'Invalid model file format. Sovereign AI only loads .gguf model files.',
      );
    }

    final file = File(trimmedPath);
    if (!file.existsSync() || !FileSystemEntity.isFileSync(trimmedPath)) {
      _status = ModelLoadStatus.error;
      throw const InferenceException(
        'Selected model file could not be found or is not a regular file.',
      );
    }

    final fileSize = file.lengthSync();
    if (fileSize < 1024 * 1024) {
      _status = ModelLoadStatus.error;
      throw const InferenceException(
        'The selected file is too small to be a valid GGUF model.',
      );
    }

    // Validate GGUF file format magic header bytes (0x47, 0x47, 0x55, 0x46 / "GGUF")
    // to reject corrupt, truncated, HTML 404, or Git LFS pointer files before invoking native code.
    RandomAccessFile? raf;
    try {
      raf = file.openSync(mode: FileMode.read);
      final header = raf.readSync(4);
      if (header.length < 4 ||
          header[0] != 0x47 || // 'G'
          header[1] != 0x47 || // 'G'
          header[2] != 0x55 || // 'U'
          header[3] != 0x46) {
        // 'F'
        _status = ModelLoadStatus.error;
        throw const InferenceException(
          'Corrupted or invalid GGUF file header. The file does not contain valid GGUF magic bytes (may be an incomplete download or HTML error page).',
        );
      }
    } on InferenceException {
      _status = ModelLoadStatus.error;
      rethrow;
    } catch (e) {
      _status = ModelLoadStatus.error;
      throw InferenceException(
        'Unable to read model file: ${e.toString().split('\n').first}',
      );
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }

    // Release any previously loaded model to enforce strict single-model memory safety
    await unloadModel();

    _status = ModelLoadStatus.loading;

    try {
      final modelSource = ModelSource.parse(trimmedPath);
      final model = LlamaModel(modelSource);

      final modelParams = ModelParams(
        contextSize: contextWindow > 0 ? contextWindow : 2048,
        gpuLayers: useGpu ? 99 : 0,
      );

      _engine = await LlamaEngine.load(model, params: modelParams);

      _currentModelPath = trimmedPath;
      _currentModelName = _extractFileName(trimmedPath);
      _status = ModelLoadStatus.loaded;
    } on LlamaStateException catch (e) {
      _status = ModelLoadStatus.error;
      await unloadModel();
      _status = ModelLoadStatus.error;
      throw InferenceException(
        'Model engine encountered an initialization state error: ${e.message}',
      );
    } catch (e) {
      _status = ModelLoadStatus.error;
      await unloadModel();
      _status = ModelLoadStatus.error;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('memory') ||
          errStr.contains('alloc') ||
          errStr.contains('oom')) {
        throw const InferenceException(
          'Insufficient memory: Your device does not have enough available RAM or VRAM '
          'to load this model. Try a smaller quantized model or reduce the context window.',
        );
      } else if (errStr.contains('magic') ||
          errStr.contains('format') ||
          errStr.contains('header')) {
        throw const InferenceException(
          'Corrupted or unsupported GGUF file format. Please verify the model was converted with a recent llama.cpp build.',
        );
      } else {
        throw const InferenceException(
          'Failed to load model weights. Please check that the file is a compatible GGUF model.',
        );
      }
    }
  }

  @override
  Future<void> unloadModel() async {
    if (_status == ModelLoadStatus.unloading) return;

    if (_isGenerating || _status == ModelLoadStatus.generating) {
      await stopGeneration();
    }

    _status = ModelLoadStatus.unloading;

    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {
        // Suppress native disposal cleanup errors
      } finally {
        _engine = null;
        _currentModelPath = null;
        _currentModelName = null;
      }
    }
    _status = ModelLoadStatus.unloaded;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) {
    if (_status == ModelLoadStatus.unloaded || _engine == null) {
      throw const InferenceException(
        'Inference engine offline: No model is currently loaded in memory.',
      );
    }

    if (_status == ModelLoadStatus.loading) {
      throw const InferenceException(
        'Model is currently loading into memory. Please wait for loading to complete.',
      );
    }

    if (_status == ModelLoadStatus.unloading) {
      throw const InferenceException(
        'Model is currently being unloaded from memory.',
      );
    }

    if (_isGenerating || _status == ModelLoadStatus.generating) {
      throw const InferenceException(
        'A generation task is already in progress. Please stop or wait for it to complete.',
      );
    }

    if (_status == ModelLoadStatus.error) {
      throw const InferenceException(
        'Inference engine is in an error state. Please reload the model.',
      );
    }

    _isGenerating = true;
    _status = ModelLoadStatus.generating;

    late final StreamController<String> controller;
    controller = StreamController<String>(
      onCancel: () async {
        await stopGeneration();
      },
    );
    _activeController = controller;

    final llamaMessages = <LlamaChatMessage>[];

    // Include system prompt if configured
    if (settings.systemPrompt.trim().isNotEmpty) {
      llamaMessages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: settings.systemPrompt.trim(),
        ),
      );
    }

    for (final msg in messages) {
      if (msg.content.trim().isEmpty) continue;
      switch (msg.role) {
        case MessageRole.user:
          llamaMessages.add(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: msg.content,
            ),
          );
          break;
        case MessageRole.assistant:
          llamaMessages.add(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: msg.content,
            ),
          );
          break;
        case MessageRole.system:
          llamaMessages.add(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: msg.content,
            ),
          );
          break;
      }
    }

    final genParams = GenerationParams(
      maxTokens: settings.maxTokens > 0 ? settings.maxTokens : 1024,
      temp: settings.temperature,
      topP: settings.topP,
    );

    try {
      final chunkStream = _engine!.create(llamaMessages, params: genParams);

      _activeSubscription = chunkStream.listen(
        (chunk) {
          final token = chunk.text;
          if (token.isNotEmpty) {
            controller.add(token);
          }
        },
        onError: (Object error) {
          _isGenerating = false;
          if (_status == ModelLoadStatus.generating) {
            _status = _engine != null
                ? ModelLoadStatus.loaded
                : ModelLoadStatus.unloaded;
          }
          _activeSubscription = null;
          final errorMsg = error.toString().toLowerCase();
          if (errorMsg.contains('cancel')) {
            controller.close();
          } else {
            controller.addError(
              const InferenceException(
                'Inference error encountered while generating tokens.',
              ),
            );
          }
        },
        onDone: () {
          _isGenerating = false;
          if (_status == ModelLoadStatus.generating) {
            _status = _engine != null
                ? ModelLoadStatus.loaded
                : ModelLoadStatus.unloaded;
          }
          _activeSubscription = null;
          controller.close();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isGenerating = false;
      if (_status == ModelLoadStatus.generating) {
        _status = _engine != null
            ? ModelLoadStatus.loaded
            : ModelLoadStatus.unloaded;
      }
      _activeSubscription = null;
      controller.addError(
        InferenceException(
          'Failed to start generation: ${e is InferenceException ? e.message : 'Engine error.'}',
        ),
      );
      controller.close();
    }

    return controller.stream;
  }

  @override
  Future<void> stopGeneration() async {
    try {
      if (_activeSubscription != null) {
        await _activeSubscription!.cancel();
      }
      if (_activeController != null && !_activeController!.isClosed) {
        await _activeController!.close();
      }
    } catch (_) {
      // Safe cancellation
    } finally {
      _activeSubscription = null;
      _activeController = null;
      _isGenerating = false;
      if (_status == ModelLoadStatus.generating) {
        _status = _engine != null
            ? ModelLoadStatus.loaded
            : ModelLoadStatus.unloaded;
      }
    }
  }

  @override
  Future<void> dispose() async {
    await unloadModel();
  }

  String _extractFileName(String path) {
    final separator = path.contains('\\') ? '\\' : '/';
    return path.split(separator).last;
  }
}

class InferenceException implements Exception {
  final String message;
  const InferenceException(this.message);

  @override
  String toString() => message;
}
