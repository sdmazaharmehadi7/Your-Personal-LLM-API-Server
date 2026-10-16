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
  String? _modelPath;
  String? _modelName;
  StreamController<String>? _controller;

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get isGenerating => _isGenerating;

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
    await unloadModel();
    if (!filePath.endsWith('.gguf')) {
      throw const InferenceException(
        'Invalid file format: must end with .gguf',
      );
    }
    _isLoaded = true;
    _modelPath = filePath;
    _modelName = 'TestModel';
  }

  @override
  Future<void> unloadModel() async {
    await stopGeneration();
    _isLoaded = false;
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
      throw const InferenceException('Generation already in progress');
    }

    _isGenerating = true;
    _controller = StreamController<String>();

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
  });
}
