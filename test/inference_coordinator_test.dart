import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/inference_coordinator.dart';
import 'package:sovereign_ai/services/inference_service.dart';
import 'package:sovereign_ai/state/chat_state.dart';
import 'package:sovereign_ai/state/model_state.dart';

ChatMessage _msg(String id, String content) => ChatMessage(
  id: id,
  role: MessageRole.user,
  content: content,
  timestamp: DateTime.now(),
);

class ControllableFakeInferenceService implements IInferenceService {
  bool _isLoaded = false;
  bool _isGenerating = false;
  ModelLoadStatus _status = ModelLoadStatus.unloaded;
  String? _modelPath;
  String? _modelName;
  StreamController<String>? _activeController;

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get isGenerating => _isGenerating;

  @override
  ModelLoadStatus get status => _status;

  @override
  String? get currentModelPath => _modelPath;

  @override
  String? get currentModelName => _modelName;

  @override
  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
  }) async {
    if (_isGenerating) {
      await stopGeneration();
    }
    _isLoaded = true;
    _status = ModelLoadStatus.loaded;
    _modelPath = filePath;
    _modelName = filePath.split('/').last;
  }

  @override
  Future<void> unloadModel() async {
    await stopGeneration();
    _isLoaded = false;
    _status = ModelLoadStatus.unloaded;
    _modelPath = null;
    _modelName = null;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) {
    if (!_isLoaded) {
      throw const InferenceException('No model loaded');
    }
    if (_isGenerating) {
      throw const InferenceException('Native engine is already generating');
    }

    _isGenerating = true;
    _status = ModelLoadStatus.generating;

    final controller = StreamController<String>(
      onCancel: () async {
        await stopGeneration();
      },
    );
    _activeController = controller;
    return controller.stream;
  }

  void emitToken(String token) {
    if (_activeController != null && !_activeController!.isClosed) {
      _activeController!.add(token);
    }
  }

  void emitError(Object error) {
    if (_activeController != null && !_activeController!.isClosed) {
      _activeController!.addError(error);
    }
  }

  void completeGeneration() {
    if (_activeController != null && !_activeController!.isClosed) {
      _activeController!.close();
    }
    _isGenerating = false;
    _status = _isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded;
  }

  @override
  Future<void> stopGeneration() async {
    if (_activeController != null && !_activeController!.isClosed) {
      await _activeController!.close();
    }
    _isGenerating = false;
    if (_status == ModelLoadStatus.generating) {
      _status = _isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded;
    }
  }

  @override
  Future<void> dispose() async {
    await unloadModel();
  }
}

void main() {
  group('InferenceCoordinator Unit Tests', () {
    late ControllableFakeInferenceService fakeService;
    late InferenceCoordinator coordinator;

    setUp(() {
      fakeService = ControllableFakeInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: fakeService,
        maxQueueSize: 2,
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Initial coordinator state is unloaded and idle', () {
      expect(coordinator.isLoaded, isFalse);
      expect(coordinator.isGenerating, isFalse);
      expect(coordinator.status, ModelLoadStatus.unloaded);
      expect(coordinator.queueLength, 0);
      expect(coordinator.activeRequestId, isNull);
    });

    test('loadModel transitions status and avoids duplicate reloads', () async {
      final statuses = <ModelLoadStatus>[];
      final sub = coordinator.statusStream.listen(statuses.add);

      await coordinator.loadModel('/path/to/model_a.gguf');
      expect(coordinator.isLoaded, isTrue);
      expect(coordinator.status, ModelLoadStatus.loaded);
      expect(coordinator.currentModelPath, '/path/to/model_a.gguf');

      // Attempt duplicate reload of the exact same path
      await coordinator.loadModel('/path/to/model_a.gguf');
      expect(coordinator.currentModelPath, '/path/to/model_a.gguf');

      await sub.cancel();
      expect(
        statuses,
        containsAllInOrder([ModelLoadStatus.loading, ModelLoadStatus.loaded]),
      );
    });

    test('Submitting request when model is not loaded throws InferenceModelNotLoadedException', () async {
      expect(
        () => coordinator.generate(
          messages: [_msg('1', 'Hi')],
          settings: const GenerationSettings(),
          requestId: 'req_1',
        ),
        throwsA(isA<InferenceModelNotLoadedException>()),
      );
    });

    test('Single request generates tokens and completes correctly', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      final stream = await coordinator.generate(
        messages: [_msg('1', 'Hi')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      expect(coordinator.isGenerating, isTrue);
      expect(coordinator.activeRequestId, 'req_1');

      final receivedTokens = <String>[];
      final completer = Completer<void>();

      stream.listen(receivedTokens.add, onDone: () => completer.complete());

      fakeService.emitToken('Hello');
      fakeService.emitToken(' world');
      fakeService.completeGeneration();

      await completer.future;

      expect(receivedTokens, ['Hello', ' world']);
      expect(coordinator.isGenerating, isFalse);
      expect(coordinator.activeRequestId, isNull);
      expect(coordinator.status, ModelLoadStatus.loaded);
    });

    test('Concurrent requests are serialized into FIFO queue and processed sequentially', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      // Request 1 starts immediately
      final stream1 = await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );
      expect(coordinator.activeRequestId, 'req_1');
      expect(coordinator.queueLength, 0);

      // Request 2 is enqueued
      final stream2 = await coordinator.generate(
        messages: [_msg('2', 'Req 2')],
        settings: const GenerationSettings(),
        requestId: 'req_2',
      );
      expect(coordinator.queueLength, 1);

      // Collect tokens for Req 1
      final tokens1 = <String>[];
      final done1 = Completer<void>();
      stream1.listen(tokens1.add, onDone: () => done1.complete());

      fakeService.emitToken('Token 1');
      fakeService.completeGeneration();
      await done1.future;
      expect(tokens1, ['Token 1']);

      // Now Request 2 should have started
      expect(coordinator.activeRequestId, 'req_2');
      expect(coordinator.queueLength, 0);

      final tokens2 = <String>[];
      final done2 = Completer<void>();
      stream2.listen(tokens2.add, onDone: () => done2.complete());

      fakeService.emitToken('Token 2');
      fakeService.completeGeneration();
      await done2.future;
      expect(tokens2, ['Token 2']);
      expect(coordinator.isGenerating, isFalse);
    });

    test('Queue rejects requests when maxQueueSize is exceeded', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      // Active
      await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      // Queue slot 1
      await coordinator.generate(
        messages: [_msg('2', 'Req 2')],
        settings: const GenerationSettings(),
        requestId: 'req_2',
      );

      // Queue slot 2 (queue full at 2)
      await coordinator.generate(
        messages: [_msg('3', 'Req 3')],
        settings: const GenerationSettings(),
        requestId: 'req_3',
      );

      expect(coordinator.queueLength, 2);

      // 4th request must be rejected with InferenceQueueFullException
      expect(
        () => coordinator.generate(
          messages: [_msg('4', 'Req 4')],
          settings: const GenerationSettings(),
          requestId: 'req_4',
        ),
        throwsA(isA<InferenceQueueFullException>()),
      );

      expect(coordinator.queueLength, 2);

      // Clean up requests
      await coordinator.stopAll();
      expect(coordinator.queueLength, 0);
      expect(coordinator.isGenerating, isFalse);
    });

    test('Cancelling active request halts generation and triggers next queued request', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      final stream1 = await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      final stream2 = await coordinator.generate(
        messages: [_msg('2', 'Req 2')],
        settings: const GenerationSettings(),
        requestId: 'req_2',
      );

      expect(coordinator.activeRequestId, 'req_1');
      expect(coordinator.queueLength, 1);

      final done1 = Completer<void>();
      stream1.listen((_) {}, onDone: () => done1.complete());

      // Cancel req_1
      final cancelled = await coordinator.cancelRequest('req_1');
      expect(cancelled, isTrue);

      await done1.future;

      // Req 2 automatically becomes active
      expect(coordinator.activeRequestId, 'req_2');
      expect(coordinator.queueLength, 0);

      fakeService.emitToken('Token 2');
      fakeService.completeGeneration();
      await stream2.drain();
    });

    test('Cancelling queued request removes it from queue without affecting active request', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      final stream1 = await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      final stream2 = await coordinator.generate(
        messages: [_msg('2', 'Req 2')],
        settings: const GenerationSettings(),
        requestId: 'req_2',
      );

      expect(coordinator.activeRequestId, 'req_1');
      expect(coordinator.queueLength, 1);

      // Cancel req_2 (which is waiting in queue)
      final cancelled = await coordinator.cancelRequest('req_2');
      expect(cancelled, isTrue);
      expect(coordinator.queueLength, 0);
      expect(coordinator.activeRequestId, 'req_1');

      // The stream for req_2 completes empty
      final tokens2 = await stream2.toList();
      expect(tokens2, isEmpty);

      // Active request completes normally
      fakeService.emitToken('Active done');
      fakeService.completeGeneration();
      final tokens1 = await stream1.toList();
      expect(tokens1, ['Active done']);
    });

    test('Cancelling non-existent requestId returns false safely', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      final cancelled = await coordinator.cancelRequest('non_existent');
      expect(cancelled, isFalse);
    });

    test('Error during inference clears active request and allows queued request to run', () async {
      await coordinator.loadModel('/path/to/model.gguf');

      final stream1 = await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      final stream2 = await coordinator.generate(
        messages: [_msg('2', 'Req 2')],
        settings: const GenerationSettings(),
        requestId: 'req_2',
      );

      final err1 = Completer<Object>();
      stream1.listen((_) {}, onError: (e) => err1.complete(e));

      // Inject error into request 1
      fakeService.emitError(
        const InferenceException('Native buffer underflow'),
      );
      fakeService.completeGeneration();

      final caughtError = await err1.future;
      expect(caughtError, isA<InferenceException>());

      // Request 2 should proceed despite Request 1 error
      expect(coordinator.activeRequestId, 'req_2');

      fakeService.emitToken('Recovered');
      fakeService.completeGeneration();
      final tokens2 = await stream2.toList();
      expect(tokens2, ['Recovered']);
      expect(coordinator.status, ModelLoadStatus.loaded);
    });

    test('Model switching is rejected while generation is active', () async {
      await coordinator.loadModel('/path/to/model_a.gguf');

      final stream1 = await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      expect(
        () => coordinator.loadModel('/path/to/model_b.gguf'),
        throwsA(isA<InferenceException>()),
      );

      await coordinator.cancelRequest('req_1');
      await stream1.drain().catchError((_) => null);
    });

    test('Unload is rejected while generating unless force is true', () async {
      await coordinator.loadModel('/path/to/model_a.gguf');

      await coordinator.generate(
        messages: [_msg('1', 'Req 1')],
        settings: const GenerationSettings(),
        requestId: 'req_1',
      );

      expect(
        () => coordinator.unloadModel(),
        throwsA(isA<InferenceException>()),
      );

      // Force unload succeeds and halts generation
      await coordinator.unloadModel(force: true);
      expect(coordinator.isLoaded, isFalse);
      expect(coordinator.isGenerating, isFalse);
      expect(coordinator.status, ModelLoadStatus.unloaded);
    });
  });

  group('InferenceCoordinator Integration with ModelState & ChatState', () {
    late ControllableFakeInferenceService fakeService;
    late InferenceCoordinator coordinator;
    late ModelState modelState;
    late ChatState chatState;

    setUp(() {
      fakeService = ControllableFakeInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: fakeService,
        maxQueueSize: 2,
      );
      modelState = ModelState(
        coordinator: coordinator,
        inferenceService: fakeService,
      );
      chatState = ChatState(modelState: modelState);
    });

    tearDown(() {
      chatState.dispose();
      modelState.dispose();
      coordinator.dispose();
    });

    test(
      'ChatState uses coordinator and updates model status during generation',
      () async {
        await modelState.loadLocalModelFile('/models/llama.gguf');
        expect(modelState.hasLoadedModel, isTrue);
        expect(modelState.activeModel!.loadStatus, ModelLoadStatus.loaded);

        final sendFuture = chatState.sendMessage(
          'Hello coordinator',
          settings: const GenerationSettings(),
          modelState: modelState,
        );

        // Give microtasks a beat to start coordinator generation
        await Future.delayed(const Duration(milliseconds: 10));

        expect(coordinator.isGenerating, isTrue);
        expect(coordinator.activeRequestId, 'ui_chat');
        expect(modelState.activeModel!.loadStatus, ModelLoadStatus.generating);

        fakeService.emitToken('Response');
        fakeService.completeGeneration();

        await sendFuture;

        expect(coordinator.isGenerating, isFalse);
        expect(modelState.activeModel!.loadStatus, ModelLoadStatus.loaded);
        expect(chatState.isGenerating, isFalse);
      },
    );

    test(
      'ChatState stopGeneration cancels ui_chat on coordinator cleanly',
      () async {
        await modelState.loadLocalModelFile('/models/llama.gguf');

        final sendFuture = chatState.sendMessage(
          'Generate stream',
          settings: const GenerationSettings(),
          modelState: modelState,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        expect(coordinator.isGenerating, isTrue);

        await chatState.stopGeneration(modelState: modelState);

        expect(coordinator.isGenerating, isFalse);
        expect(coordinator.activeRequestId, isNull);

        await sendFuture;
        expect(chatState.isGenerating, isFalse);
      },
    );
  });
}
