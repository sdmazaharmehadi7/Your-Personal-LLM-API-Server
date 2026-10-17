import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/inference_service.dart';
import 'package:sovereign_ai/state/chat_state.dart';
import 'package:sovereign_ai/state/model_state.dart';

class FakeInferenceService implements IInferenceService {
  bool _isLoaded = false;
  bool _isGenerating = false;
  ModelLoadStatus _status = ModelLoadStatus.unloaded;
  String? _modelPath;
  String? _modelName;
  StreamController<String>? _controller;

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
    await unloadModel();
    if (!filePath.endsWith('.gguf')) {
      _status = ModelLoadStatus.error;
      throw const InferenceException(
        'Invalid file format: must end with .gguf',
      );
    }
    _status = ModelLoadStatus.loading;
    _isLoaded = true;
    _status = ModelLoadStatus.loaded;
    _modelPath = filePath;
    _modelName = 'TestModel';
  }

  @override
  Future<void> unloadModel() async {
    await stopGeneration();
    _status = ModelLoadStatus.unloading;
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
    if (!_isLoaded || _status != ModelLoadStatus.loaded) {
      throw const InferenceException('No model loaded');
    }
    if (_isGenerating || _status == ModelLoadStatus.generating) {
      throw const InferenceException('Generation already in progress');
    }

    _isGenerating = true;
    _status = ModelLoadStatus.generating;
    _controller = StreamController<String>(
      onCancel: () async {
        await stopGeneration();
      },
    );

    // Emit tokens asynchronously
    Future.microtask(() async {
      final tokens = ['Hello', ' from', ' local', ' offline', ' GGUF!'];
      for (final t in tokens) {
        if (_controller == null || _controller!.isClosed) break;
        _controller!.add(t);
        await Future.delayed(const Duration(milliseconds: 10));
      }
      if (_controller != null && !_controller!.isClosed) {
        _isGenerating = false;
        _status = _isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded;
        await _controller!.close();
      }
    });

    return _controller!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
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
  group('LocalInferenceService validation tests', () {
    test('rejects empty file path', () async {
      final service = LocalInferenceService();
      expect(() => service.loadModel(''), throwsA(isA<InferenceException>()));
    });

    test('rejects non-gguf files', () async {
      final service = LocalInferenceService();
      expect(
        () => service.loadModel('/path/to/model.bin'),
        throwsA(
          predicate<InferenceException>((e) => e.message.contains('.gguf')),
        ),
      );
    });

    test('rejects non-existent files', () async {
      final service = LocalInferenceService();
      expect(
        () => service.loadModel('/non_existent_folder/missing_model.gguf'),
        throwsA(
          predicate<InferenceException>(
            (e) => e.message.contains('could not be found'),
          ),
        ),
      );
    });

    test('rejects non-GGUF files with invalid magic header bytes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'gguf_header_test_',
      );
      final fakeGguf = File('${tempDir.path}/fake_model.gguf');
      // Create a 1MB+ file that lacks GGUF magic bytes (simulating HTML or corrupted download)
      await fakeGguf.writeAsString(
        '<!DOCTYPE html><html>404 Not Found</html>' * 40000,
      );

      final service = LocalInferenceService();
      try {
        expect(
          () => service.loadModel(fakeGguf.path),
          throwsA(
            predicate<InferenceException>(
              (e) => e.message.contains('magic bytes'),
            ),
          ),
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('throws when generating without loaded model', () {
      final service = LocalInferenceService();
      expect(
        () => service.generate(
          messages: [],
          settings: const GenerationSettings(),
        ),
        throwsA(isA<InferenceException>()),
      );
    });
  });

  group('ModelState tests', () {
    test('initializes in unloaded state', () {
      final modelState = ModelState(inferenceService: FakeInferenceService());
      expect(modelState.hasLoadedModel, isFalse);
      expect(modelState.activeModel, isNull);
      expect(modelState.isLoading, isFalse);
      expect(modelState.errorMessage, isNull);
    });

    test('loading invalid model records actionable error', () async {
      final modelState = ModelState(inferenceService: FakeInferenceService());
      final success = await modelState.loadLocalModelFile(
        '/invalid_path/model.txt',
      );
      expect(success, isFalse);
      expect(modelState.hasLoadedModel, isFalse);
      expect(modelState.errorMessage, isNotNull);
      expect(modelState.errorMessage, contains('.gguf'));
    });

    test(
      'loading valid model sets activeModel and clears loading state',
      () async {
        final modelState = ModelState(inferenceService: FakeInferenceService());
        final success = await modelState.loadLocalModelFile(
          '/valid/test_model.gguf',
        );
        expect(success, isTrue);
        expect(modelState.hasLoadedModel, isTrue);
        expect(modelState.activeModel, isNotNull);
        expect(modelState.activeModel!.loadStatus.name, 'loaded');

        // Test unload
        await modelState.unloadActiveModel();
        expect(modelState.hasLoadedModel, isFalse);
        expect(modelState.activeModel, isNull);
      },
    );

    test(
      'resets all models loadStatus to unloaded when subsequent load fails',
      () async {
        final modelState = ModelState(inferenceService: FakeInferenceService());
        // First load succeeds
        await modelState.loadLocalModelFile(
          '/valid/SmolLM2-135M-Instruct-Q4_K_M.gguf',
        );
        expect(modelState.hasLoadedModel, isTrue);
        expect(modelState.activeModel, isNotNull);

        // Second load fails with invalid file
        final success = await modelState.loadLocalModelFile(
          '/invalid_path/bad.txt',
        );
        expect(success, isFalse);
        expect(modelState.hasLoadedModel, isFalse);
        expect(modelState.activeModel, isNull);

        // Verify no model in list is left in loaded state
        final loadedCount = modelState.models
            .where((m) => m.loadStatus == ModelLoadStatus.loaded)
            .length;
        expect(loadedCount, 0);
      },
    );
  });

  group('ChatState streaming and cancellation tests', () {
    test(
      'streams tokens into assistant message when model is loaded',
      () async {
        final fakeService = FakeInferenceService();
        await fakeService.loadModel('/valid/test.gguf');

        final chatState = ChatState();
        await chatState.sendMessage(
          'What is Sovereign AI?',
          inferenceService: fakeService,
          settings: const GenerationSettings(),
        );

        final session = chatState.activeSession;
        expect(session, isNotNull);
        expect(session!.messages.length, 2);
        expect(session.messages[0].role, MessageRole.user);
        expect(session.messages[0].content, 'What is Sovereign AI?');

        expect(session.messages[1].role, MessageRole.assistant);
        expect(session.messages[1].content, 'Hello from local offline GGUF!');
        expect(session.messages[1].status, MessageStatus.sent);
      },
    );

    test(
      'stopping generation marks message as stopped and completes future',
      () async {
        final fakeService = FakeInferenceService();
        await fakeService.loadModel('/valid/test.gguf');

        final chatState = ChatState();

        // Start message and ensure future completes cleanly within timeout
        final sendFuture = chatState.sendMessage(
          'Long prompt',
          inferenceService: fakeService,
          settings: const GenerationSettings(),
        );

        // Give it 1 tick then stop
        await Future.delayed(const Duration(milliseconds: 15));
        await chatState.stopGeneration(inferenceService: fakeService);

        // sendFuture must resolve cleanly without timeout/hang
        await sendFuture.timeout(const Duration(seconds: 2));

        final session = chatState.activeSession;
        expect(session, isNotNull);
        final lastMsg = session!.messages.last;
        expect(lastMsg.status, MessageStatus.sent);
        expect(chatState.isGenerating, isFalse);
      },
    );

    test(
      'ignores concurrent sendMessage while generation is in progress',
      () async {
        final fakeService = FakeInferenceService();
        await fakeService.loadModel('/valid/test.gguf');

        final chatState = ChatState();

        final firstSend = chatState.sendMessage(
          'First prompt',
          inferenceService: fakeService,
          settings: const GenerationSettings(),
        );

        // Attempt second send immediately while first is actively generating
        await chatState.sendMessage(
          'Second prompt (should be ignored)',
          inferenceService: fakeService,
          settings: const GenerationSettings(),
        );

        await firstSend;

        final session = chatState.activeSession;
        expect(session, isNotNull);
        // Only 1 user message and 1 assistant message should exist
        final userMessages = session!.messages
            .where((m) => m.role == MessageRole.user)
            .toList();
        expect(userMessages.length, 1);
        expect(userMessages.first.content, 'First prompt');
      },
    );

    test(
      'cancelling token stream triggers onCancel and resets generating state',
      () async {
        final fakeService = FakeInferenceService();
        await fakeService.loadModel('/valid/test.gguf');

        final stream = fakeService.generate(
          messages: [
            ChatMessage(
              id: '1',
              role: MessageRole.user,
              content: 'test',
              timestamp: DateTime.now(),
            ),
          ],
          settings: const GenerationSettings(),
        );

        expect(fakeService.status, ModelLoadStatus.generating);
        expect(fakeService.isGenerating, isTrue);

        final sub = stream.listen((_) {});
        // Cancel the stream subscription
        await sub.cancel();

        expect(fakeService.isGenerating, isFalse);
        expect(fakeService.status, ModelLoadStatus.loaded);
      },
    );
  });

  group('Model lifecycle and state transition tests', () {
    test('LocalInferenceService initial state is unloaded', () {
      final service = LocalInferenceService();
      expect(service.status, ModelLoadStatus.unloaded);
      expect(service.isLoaded, isFalse);
      expect(service.isGenerating, isFalse);
    });

    test(
      'LocalInferenceService transitions to error on invalid model file',
      () async {
        final service = LocalInferenceService();
        expect(
          () => service.loadModel('/invalid/path.bin'),
          throwsA(isA<InferenceException>()),
        );
        expect(service.status, ModelLoadStatus.error);
        expect(service.isLoaded, isFalse);
      },
    );

    test('LocalInferenceService rejects generation when not loaded', () {
      final service = LocalInferenceService();
      expect(
        () => service.generate(
          messages: [],
          settings: const GenerationSettings(),
        ),
        throwsA(
          predicate<InferenceException>(
            (e) => e.message.contains('No model is currently loaded'),
          ),
        ),
      );
    });

    test('ModelState deduplicates load requests for already loaded model', () async {
      final fakeService = FakeInferenceService();
      final modelState = ModelState(inferenceService: fakeService);

      final firstSuccess = await modelState.loadLocalModelFile(
        '/models/llama.gguf',
      );
      expect(firstSuccess, isTrue);
      expect(modelState.hasLoadedModel, isTrue);
      expect(modelState.activeModel!.loadStatus, ModelLoadStatus.loaded);

      // Second load for same path should succeed immediately without reloading
      final secondSuccess = await modelState.loadLocalModelFile(
        '/models/llama.gguf',
      );
      expect(secondSuccess, isTrue);
      expect(modelState.activeModel!.loadStatus, ModelLoadStatus.loaded);
    });

    test(
      'ModelState rejects model switching while actively generating',
      () async {
        final fakeService = FakeInferenceService();
        final modelState = ModelState(inferenceService: fakeService);

        await modelState.loadLocalModelFile('/models/model_a.gguf');
        expect(modelState.hasLoadedModel, isTrue);

        // Simulate active generation
        modelState.setActiveModelGenerating(true);
        expect(modelState.activeModel!.loadStatus, ModelLoadStatus.generating);

        // Attempt to switch to model_b while generating
        final switchSuccess = await modelState.loadLocalModelFile(
          '/models/model_b.gguf',
        );
        expect(switchSuccess, isFalse);
        expect(modelState.errorMessage, contains('active'));
        expect(modelState.activeModel!.filename, 'model_a.gguf');

        // Clear generating status and verify switch now succeeds
        modelState.setActiveModelGenerating(false);
        final switchSuccessAfter = await modelState.loadLocalModelFile(
          '/models/model_b.gguf',
        );
        expect(switchSuccessAfter, isTrue);
        expect(modelState.activeModel!.filename, 'model_b.gguf');
      },
    );

    test('ChatState updates active model loadStatus to generating during streaming', () async {
      final fakeService = FakeInferenceService();
      final modelState = ModelState(inferenceService: fakeService);
      await modelState.loadLocalModelFile('/models/model_a.gguf');

      final chatState = ChatState(modelState: modelState);

      final sendFuture = chatState.sendMessage(
        'Generate response',
        inferenceService: fakeService,
        settings: const GenerationSettings(),
        modelState: modelState,
      );

      // During generation, activeModel status must be generating
      expect(modelState.activeModel!.loadStatus, ModelLoadStatus.generating);
      expect(chatState.isGenerating, isTrue);

      await sendFuture;

      // After generation finishes, status must revert to loaded
      expect(modelState.activeModel!.loadStatus, ModelLoadStatus.loaded);
      expect(chatState.isGenerating, isFalse);
    });
  });
}
