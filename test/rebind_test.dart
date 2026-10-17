import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/api_server/api_key_service.dart';
import 'package:sovereign_ai/services/api_server/local_api_server.dart';
import 'package:sovereign_ai/services/inference_coordinator.dart';
import 'package:sovereign_ai/services/inference_service.dart';

class MockableInferenceService implements IInferenceService {
  bool _isLoaded = false;
  final bool _isGenerating = false;
  ModelLoadStatus _status = ModelLoadStatus.unloaded;
  String? _modelPath;
  String? _modelName;

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
    _isLoaded = true;
    _status = ModelLoadStatus.loaded;
    _modelPath = filePath;
    _modelName = filePath.split('/').last;
  }

  @override
  Future<void> unloadModel() async {
    _isLoaded = false;
    _status = ModelLoadStatus.unloaded;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) {
    return Stream.value('test');
  }

  @override
  Future<void> stopGeneration() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('Rapid toggling of external connections on fixed port 8080', () async {
    final coordinator = InferenceCoordinator(
      inferenceService: MockableInferenceService(),
    );
    final tempDir = Directory.systemTemp.createTempSync('sov_test_rebind_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final apiKeyService = ApiKeyService(
      storage: FileApiKeyStorage(customBaseDirectory: tempDir),
    );
    final server = LocalApiServer(
      coordinator: coordinator,
      apiKeyService: apiKeyService,
      initialPort: 8080,
    );
    addTearDown(() => server.stop());

    // Start on port 8080
    var started = await server.start(port: 8080);
    expect(
      started,
      isTrue,
      reason: 'Initial start failed: ${server.errorMessage}',
    );
    expect(server.isRunning, isTrue);

    // Toggle 1: enable external
    var toggled = await server.setAllowExternalConnections(true);
    expect(
      toggled,
      isTrue,
      reason: 'Toggle to true failed: ${server.errorMessage}',
    );
    expect(
      server.isRunning,
      isTrue,
      reason: 'Server stopped after toggle true: ${server.errorMessage}',
    );

    // Toggle 2: untoggle back to false
    var untoggled = await server.setAllowExternalConnections(false);
    expect(
      untoggled,
      isTrue,
      reason: 'Toggle to false failed: ${server.errorMessage}',
    );
    expect(
      server.isRunning,
      isTrue,
      reason: 'Server stopped after untoggle false: ${server.errorMessage}',
    );

    // Toggle 3: toggle again
    toggled = await server.setAllowExternalConnections(true);
    expect(
      toggled,
      isTrue,
      reason: 'Toggle to true again failed: ${server.errorMessage}',
    );
    expect(
      server.isRunning,
      isTrue,
      reason: 'Server stopped after second toggle: ${server.errorMessage}',
    );
  });
}
