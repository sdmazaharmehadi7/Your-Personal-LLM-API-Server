import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/generation_settings.dart';
import '../models/local_model.dart';
import 'inference_service.dart';

/// Specialized exception thrown when the inference coordinator's queue is full.
class InferenceQueueFullException extends InferenceException {
  final int currentQueueSize;
  final int maxQueueSize;

  const InferenceQueueFullException({
    required this.currentQueueSize,
    required this.maxQueueSize,
    String? message,
  }) : super(
         message ??
             'Inference queue is full ($currentQueueSize/$maxQueueSize). Please retry shortly.',
       );
}

/// Specialized exception thrown when an operation cannot proceed because no model is loaded.
class InferenceModelNotLoadedException extends InferenceException {
  const InferenceModelNotLoadedException([
    super.message =
        'Inference engine offline: No model is currently loaded in memory.',
  ]);
}

/// Specialized exception thrown when an operation cannot proceed because the engine is busy.
class InferenceBusyException extends InferenceException {
  final String activeRequestId;

  const InferenceBusyException({required this.activeRequestId, String? message})
    : super(
        message ??
            'Inference engine is currently busy with task "$activeRequestId".',
      );
}

/// Public interface for the authoritative shared inference coordinator.
///
/// Both the Flutter UI and future HTTP API server consume this interface to
/// share the single in-memory model lifecycle and hardware inference context safely.
abstract class IInferenceCoordinator implements Listenable {
  /// The underlying native inference service.
  IInferenceService get inferenceService;

  /// Current model lifecycle status (unloaded, loading, loaded, generating, unloading, error).
  ModelLoadStatus get status;

  /// Whether a model is currently loaded in memory and available for generation.
  bool get isLoaded;

  /// Whether an inference generation task is currently computing tokens.
  bool get isGenerating;

  /// File path of the currently loaded model on disk.
  String? get currentModelPath;

  /// Filename or display name of the currently loaded model.
  String? get currentModelName;

  /// Metadata descriptor of the active model, if available.
  LocalModel? get activeModel;

  /// Number of generation requests currently waiting in the FIFO queue.
  int get queueLength;

  /// Maximum allowed queue size before new requests are rejected with [InferenceQueueFullException].
  int get maxQueueSize;

  /// Request ID of the currently active generation task, if any.
  String? get activeRequestId;

  /// Broadcast stream emitting lifecycle status transitions for non-UI observers (e.g. API monitors).
  Stream<ModelLoadStatus> get statusStream;

  /// Loads a GGUF model into memory.
  ///
  /// Rejects switching if any generation task is active or queued.
  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
    LocalModel? modelMetadata,
  });

  /// Unloads the active model and releases native resources.
  ///
  /// If [force] is false (default), rejects unloading if requests are active or queued.
  Future<void> unloadModel({bool force = false});

  /// Submits a generation request.
  ///
  /// If the engine is currently generating, the request is placed in a FIFO queue.
  /// If the queue is at [maxQueueSize], throws [InferenceQueueFullException].
  /// If no model is loaded, throws [InferenceModelNotLoadedException].
  Future<Stream<String>> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
    String? requestId,
  });

  /// Cancels a specific generation request by [requestId].
  ///
  /// If [requestId] matches the actively generating task, generation is halted.
  /// If [requestId] is in the queue, it is dequeued and cancelled.
  /// Cancellation of one request never cancels another consumer's request.
  /// Returns `true` if a matching task was cancelled, `false` otherwise.
  Future<bool> cancelRequest(String requestId);

  /// Cancels all active and queued requests immediately.
  Future<void> stopAll();

  /// Disposes coordinator resources.
  void dispose();
}

class _QueuedRequest {
  final String requestId;
  final List<ChatMessage> messages;
  final GenerationSettings settings;
  final Completer<Stream<String>> streamCompleter;
  final StreamController<String> tokenController;
  bool isCancelled = false;

  _QueuedRequest({
    required this.requestId,
    required this.messages,
    required this.settings,
    required this.streamCompleter,
    required this.tokenController,
  });
}

/// The authoritative shared implementation of [IInferenceCoordinator].
class InferenceCoordinator extends ChangeNotifier
    implements IInferenceCoordinator {
  static int _idCounter = 0;

  @override
  final IInferenceService inferenceService;
  @override
  final int maxQueueSize;

  final StreamController<ModelLoadStatus> _statusController =
      StreamController<ModelLoadStatus>.broadcast();

  LocalModel? _activeModel;
  String? _activeRequestId;
  StreamController<String>? _activeClientController;
  final List<_QueuedRequest> _queue = [];
  bool _isDisposed = false;

  InferenceCoordinator({
    required this.inferenceService,
    this.maxQueueSize = 2,
    LocalModel? initialModel,
  }) : _activeModel = initialModel;

  IInferenceService get _inferenceService => inferenceService;

  @override
  ModelLoadStatus get status => _inferenceService.status;

  @override
  bool get isLoaded => _inferenceService.isLoaded;

  @override
  bool get isGenerating =>
      _activeRequestId != null || _inferenceService.isGenerating;

  @override
  String? get currentModelPath => _inferenceService.currentModelPath;

  @override
  String? get currentModelName => _inferenceService.currentModelName;

  @override
  LocalModel? get activeModel => _activeModel;

  @override
  int get queueLength => _queue.length;

  @override
  String? get activeRequestId => _activeRequestId;

  @override
  Stream<ModelLoadStatus> get statusStream => _statusController.stream;

  @override
  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
    LocalModel? modelMetadata,
  }) async {
    _checkNotDisposed();

    if (isGenerating || _queue.isNotEmpty) {
      throw const InferenceException(
        'Cannot switch models while inference requests are active or queued. '
        'Please wait for in-flight tasks to complete or cancel them first.',
      );
    }

    final trimmedPath = filePath.trim();

    // Deduplicate loading if already loaded in memory
    if (isLoaded &&
        currentModelPath == trimmedPath &&
        status == ModelLoadStatus.loaded) {
      if (modelMetadata != null) {
        _activeModel = modelMetadata.copyWith(
          loadStatus: ModelLoadStatus.loaded,
        );
        notifyListeners();
      }
      return;
    }

    _notifyStatusChange(ModelLoadStatus.loading);

    try {
      await _inferenceService.loadModel(
        trimmedPath,
        contextWindow: contextWindow,
        useGpu: useGpu,
      );

      _activeModel =
          (modelMetadata ??
                  LocalModel(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    name: _inferenceService.currentModelName ?? 'Loaded Model',
                    family: 'Custom GGUF',
                    parameterSize: 'Custom',
                    quantization: 'GGUF',
                    diskSizeGb: 0.0,
                    estimatedRamGb: 1.0,
                    description: 'Imported local model file.',
                    filename:
                        _inferenceService.currentModelName ?? 'model.gguf',
                    localPath: trimmedPath,
                    loadStatus: ModelLoadStatus.loaded,
                  ))
              .copyWith(loadStatus: ModelLoadStatus.loaded);

      _notifyStatusChange(ModelLoadStatus.loaded);
    } catch (e) {
      _activeModel = null;
      _notifyStatusChange(ModelLoadStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> unloadModel({bool force = false}) async {
    _checkNotDisposed();

    if ((isGenerating || _queue.isNotEmpty) && !force) {
      throw const InferenceException(
        'Cannot unload model while inference requests are active or queued. '
        'Please stop or wait for active tasks before unloading.',
      );
    }

    if (force) {
      await stopAll();
    }

    _notifyStatusChange(ModelLoadStatus.unloading);

    try {
      await _inferenceService.unloadModel();
      _activeModel = null;
      _notifyStatusChange(ModelLoadStatus.unloaded);
    } catch (e) {
      _activeModel = null;
      _notifyStatusChange(ModelLoadStatus.error);
      rethrow;
    }
  }

  @override
  Future<Stream<String>> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
    String? requestId,
  }) async {
    _checkNotDisposed();

    if (!isLoaded) {
      throw const InferenceModelNotLoadedException();
    }

    if (status == ModelLoadStatus.loading) {
      throw const InferenceException(
        'Model is currently loading into memory. Please wait for loading to complete.',
      );
    }

    if (status == ModelLoadStatus.unloading) {
      throw const InferenceException(
        'Model is currently being unloaded from memory.',
      );
    }

    final effectiveId =
        requestId ??
        'req_${DateTime.now().microsecondsSinceEpoch}_${++_idCounter}';

    // If another request is currently running or queue has items, queue this request
    if (_activeRequestId != null) {
      if (_queue.length >= maxQueueSize) {
        throw InferenceQueueFullException(
          currentQueueSize: _queue.length,
          maxQueueSize: maxQueueSize,
        );
      }

      final queuedController = StreamController<String>();
      queuedController.onCancel = () {
        cancelRequest(effectiveId);
      };

      final queued = _QueuedRequest(
        requestId: effectiveId,
        messages: messages,
        settings: settings,
        streamCompleter: Completer<Stream<String>>(),
        tokenController: queuedController,
      );
      _queue.add(queued);
      if (!_isDisposed) notifyListeners();

      return queuedController.stream;
    }

    return _startGeneration(
      requestId: effectiveId,
      messages: messages,
      settings: settings,
    );
  }

  Future<Stream<String>> _startGeneration({
    required String requestId,
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) async {
    _activeRequestId = requestId;
    _notifyStatusChange(ModelLoadStatus.generating);

    final clientController = StreamController<String>();
    _activeClientController = clientController;
    clientController.onCancel = () {
      cancelRequest(requestId);
    };

    try {
      final engineStream = _inferenceService.generate(
        messages: messages,
        settings: settings,
      );

      engineStream.listen(
        (token) {
          if (!clientController.isClosed) {
            clientController.add(token);
          }
        },
        onError: (Object error) {
          if (!clientController.isClosed) {
            clientController.addError(error);
            clientController.close();
          }
          _finishActiveRequest(requestId);
        },
        onDone: () {
          if (!clientController.isClosed) {
            clientController.close();
          }
          _finishActiveRequest(requestId);
        },
        cancelOnError: true,
      );

      return clientController.stream;
    } catch (e) {
      if (!clientController.isClosed) {
        clientController.addError(e);
        clientController.close();
      }
      _finishActiveRequest(requestId);
      rethrow;
    }
  }

  void _finishActiveRequest(String requestId) {
    if (_activeRequestId == requestId) {
      if (_activeClientController != null &&
          !_activeClientController!.isClosed) {
        _activeClientController!.close();
      }
      _activeClientController = null;
      _activeRequestId = null;
      _notifyStatusChange(
        isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded,
      );
      _processNextQueueItem();
    }
  }

  void _processNextQueueItem() {
    if (_isDisposed || _activeRequestId != null || _queue.isEmpty) {
      return;
    }

    final next = _queue.removeAt(0);
    if (!_isDisposed) notifyListeners();

    if (next.isCancelled) {
      _processNextQueueItem();
      return;
    }

    if (!isLoaded) {
      if (!next.tokenController.isClosed) {
        next.tokenController.addError(const InferenceModelNotLoadedException());
        next.tokenController.close();
      }
      _processNextQueueItem();
      return;
    }

    _activeRequestId = next.requestId;
    _activeClientController = next.tokenController;
    _notifyStatusChange(ModelLoadStatus.generating);

    try {
      final engineStream = _inferenceService.generate(
        messages: next.messages,
        settings: next.settings,
      );

      engineStream.listen(
        (token) {
          if (!next.tokenController.isClosed) {
            next.tokenController.add(token);
          }
        },
        onError: (Object error) {
          if (!next.tokenController.isClosed) {
            next.tokenController.addError(error);
            next.tokenController.close();
          }
          _finishActiveRequest(next.requestId);
        },
        onDone: () {
          if (!next.tokenController.isClosed) {
            next.tokenController.close();
          }
          _finishActiveRequest(next.requestId);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!next.tokenController.isClosed) {
        next.tokenController.addError(e);
        next.tokenController.close();
      }
      _finishActiveRequest(next.requestId);
    }
  }

  @override
  Future<bool> cancelRequest(String requestId) async {
    // 1. Cancel active generation if matching
    if (_activeRequestId == requestId) {
      await _inferenceService.stopGeneration();
      _finishActiveRequest(requestId);
      return true;
    }

    // 2. Cancel queued request if matching
    final queueIndex = _queue.indexWhere((q) => q.requestId == requestId);
    if (queueIndex != -1) {
      final queued = _queue.removeAt(queueIndex);
      queued.isCancelled = true;
      if (!queued.tokenController.isClosed) {
        queued.tokenController.close();
      }
      if (!_isDisposed) notifyListeners();
      return true;
    }

    // 3. Not found - ensure other consumers' requests are strictly untouched
    return false;
  }

  @override
  Future<void> stopAll() async {
    for (final queued in _queue) {
      queued.isCancelled = true;
      if (!queued.tokenController.isClosed) {
        queued.tokenController.close();
      }
    }
    _queue.clear();

    if (_activeRequestId != null) {
      if (_activeClientController != null &&
          !_activeClientController!.isClosed) {
        _activeClientController!.close();
      }
      _activeClientController = null;
      _activeRequestId = null;
      await _inferenceService.stopGeneration();
    }

    if (!_isDisposed) {
      _notifyStatusChange(
        isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded,
      );
    }
  }

  void _notifyStatusChange(ModelLoadStatus newStatus) {
    if (_isDisposed) return;
    if (_activeModel != null && _activeModel!.loadStatus != newStatus) {
      _activeModel = _activeModel!.copyWith(loadStatus: newStatus);
    }
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw const InferenceException(
        'Inference coordinator has been disposed.',
      );
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final queued in _queue) {
      queued.isCancelled = true;
      if (!queued.tokenController.isClosed) {
        queued.tokenController.close();
      }
    }
    _queue.clear();
    if (_activeClientController != null && !_activeClientController!.isClosed) {
      _activeClientController!.close();
    }
    _activeClientController = null;
    _activeRequestId = null;
    _inferenceService.stopGeneration();
    _statusController.close();
    super.dispose();
  }
}
