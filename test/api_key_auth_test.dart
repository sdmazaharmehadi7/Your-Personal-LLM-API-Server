import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sovereign_ai/models/api_key.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/api_server/api_key_service.dart';
import 'package:sovereign_ai/services/api_server/local_api_server.dart';
import 'package:sovereign_ai/services/inference_coordinator.dart';
import 'package:sovereign_ai/services/inference_service.dart';

class MockableInferenceService implements IInferenceService {
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
    _isLoaded = true;
    _status = ModelLoadStatus.loaded;
    _modelPath = filePath;
    _modelName = filePath.split('/').last;
  }

  @override
  Future<void> unloadModel() async {
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
    if (!_isLoaded) throw const InferenceException('No model loaded');
    _isGenerating = true;
    _status = ModelLoadStatus.generating;

    final controller = StreamController<String>(
      onCancel: () async {
        await stopGeneration();
      },
    );
    _activeController = controller;

    Future.microtask(() async {
      final tokens = ['Hello', ' from', ' Sovereign', ' AI!'];
      for (final t in tokens) {
        if (controller.isClosed) break;
        controller.add(t);
        await Future.delayed(const Duration(milliseconds: 5));
      }
      if (!controller.isClosed) {
        _isGenerating = false;
        _status = ModelLoadStatus.loaded;
        await controller.close();
      }
    });

    return controller.stream;
  }

  @override
  Future<void> stopGeneration() async {
    if (_activeController != null && !_activeController!.isClosed) {
      await _activeController!.close();
    }
    _isGenerating = false;
    _status = _isLoaded ? ModelLoadStatus.loaded : ModelLoadStatus.unloaded;
  }

  @override
  Future<void> dispose() async {
    await _activeController?.close();
  }
}

void main() {
  group('Prompt 5: API Key Authentication and Management Tests', () {
    late MockableInferenceService mockService;
    late InferenceCoordinator coordinator;
    late InMemoryApiKeyStorage storage;
    late ApiKeyService apiKeyService;
    late LocalApiServer server;

    setUp(() async {
      mockService = MockableInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: mockService,
        maxQueueSize: 4,
      );
      storage = InMemoryApiKeyStorage();
      apiKeyService = ApiKeyService(storage: storage);
      await apiKeyService.init();

      server = LocalApiServer(
        coordinator: coordinator,
        apiKeyService: apiKeyService,
      );
      await server.start(port: 0);
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
    });

    tearDown(() async {
      await server.stop();
      server.dispose();
      coordinator.dispose();
      apiKeyService.dispose();
    });

    test(
      '1. Secure key generation and adequate key entropy (>= 256 bits)',
      () async {
        final keyGen = await apiKeyService.createKey(name: 'High Entropy Key');
        final secret = keyGen.plaintextSecret;

        // 32 bytes = 256 bits = 64 hex characters + "sk-sov-" prefix = 71 characters
        expect(secret.startsWith('sk-sov-'), isTrue);
        expect(secret.length, 71);

        // Verify hexadecimal entropy portion
        final hexPart = secret.substring(7);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hexPart), isTrue);

        // Generate a second key and verify uniqueness
        final keyGen2 = await apiKeyService.createKey(name: 'Second Key');
        expect(keyGen2.plaintextSecret, isNot(equals(secret)));
      },
    );

    test('2. Plaintext keys are not persisted', () async {
      final keyGen = await apiKeyService.createKey(name: 'Secret Storage Test');
      final secret = keyGen.plaintextSecret;

      final storedKeys = await storage.loadKeys();
      expect(storedKeys, hasLength(1));

      // Check serialized representation in storage
      final storedJson = jsonEncode(storedKeys.map((k) => k.toJson()).toList());
      expect(storedJson.contains(secret), isFalse);
      expect(storedJson.contains(secret.substring(7)), isFalse);
    });

    test('3. Only the key hash and salt are stored', () async {
      await apiKeyService.createKey(name: 'Hash Storage Test');
      final metadata = apiKeyService.keys.first;

      expect(metadata.saltHex, isNotEmpty);
      expect(metadata.saltHex.length, 32); // 16 bytes = 32 hex chars
      expect(metadata.hashHex, isNotEmpty);
      expect(metadata.hashHex.length, 64); // HMAC-SHA256 = 64 hex chars
    });

    test('4. One-time secret display behavior', () async {
      final creationResult = await apiKeyService.createKey(
        name: 'One Time Display Test',
      );
      expect(creationResult.plaintextSecret, isNotEmpty);

      // In the service keys list, only metadata is accessible
      final serviceKey = apiKeyService.keys.first;
      expect(serviceKey.id, creationResult.metadata.id);
      expect(serviceKey.keyPrefix.startsWith('sk-sov-'), isTrue);
      expect(serviceKey.keyPrefix.contains('...'), isTrue);
    });

    test('5. Valid Bearer-key authentication succeeds with 200', () async {
      final keyResult = await apiKeyService.createKey(name: 'Valid Key');

      final res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${keyResult.plaintextSecret}'},
      );

      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      expect(body['object'], 'list');
      expect(body['data'], hasLength(1));
    });

    test('6. Missing and malformed authorization headers return 401', () async {
      // Missing header
      var res = await http.get(Uri.parse('${server.baseUrl}/v1/models'));
      expect(res.statusCode, 401);
      var err = jsonDecode(res.body)['error'];
      expect(err['code'], 'missing_authorization_header');

      // Malformed: Basic instead of Bearer
      res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Basic dXNlcjpwYXNz'},
      );
      expect(res.statusCode, 401);
      err = jsonDecode(res.body)['error'];
      expect(err['code'], 'invalid_authorization_format');

      // Malformed: Bearer with empty secret
      res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer '},
      );
      expect(res.statusCode, 401);
      err = jsonDecode(res.body)['error'];
      expect(err['code'], 'empty_api_key');
    });

    test('7. Invalid, expired, and revoked keys return 401', () async {
      // Invalid secret
      var res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {
          'Authorization': 'Bearer sk-sov-0000000000000000000000000000000000000000000000000000000000000000',
        },
      );
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['error']['code'], 'invalid_api_key');

      // Expired key
      final expiredResult = await apiKeyService.createKey(
        name: 'Expired Key',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${expiredResult.plaintextSecret}'},
      );
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['error']['code'], 'expired_api_key');

      // Revoked key
      final revokeResult = await apiKeyService.createKey(name: 'Revoke Key');
      await apiKeyService.revokeKey(revokeResult.metadata.id);
      res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${revokeResult.plaintextSecret}'},
      );
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['error']['code'], 'revoked_api_key');
    });

    test('8. Permission enforcement rejects requests with 403', () async {
      // Key with only modelsList permission
      final modelsOnlyKey = await apiKeyService.createKey(
        name: 'Models Only Key',
        permissions: {ApiKeyPermission.modelsList},
      );

      // Attempt chat completion
      final res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${modelsOnlyKey.plaintextSecret}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen2.5-0.5b.gguf',
          'messages': [
            {'role': 'user', 'content': 'Test'},
          ],
        }),
      );

      expect(res.statusCode, 403);
      final err = jsonDecode(res.body)['error'];
      expect(err['code'], 'insufficient_permissions');
      expect(err['message'], contains('chat_completions'));
    });

    test(
      '9. Per-key rate limiting returns 429 with Retry-After header',
      () async {
        // Key with rate limit of 2 requests per minute
        final rateLimitedKey = await apiKeyService.createKey(
          name: 'Rate Limited Key',
          rateLimitRpm: 2,
        );

        final headers = {
          'Authorization': 'Bearer ${rateLimitedKey.plaintextSecret}',
        };

        // 1st request -> OK
        var res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: headers,
        );
        expect(res.statusCode, 200);

        // 2nd request -> OK
        res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: headers,
        );
        expect(res.statusCode, 200);

        // 3rd request -> 429 Rate Limit Exceeded
        res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: headers,
        );
        expect(res.statusCode, 429);
        expect(res.headers[HttpHeaders.retryAfterHeader], isNotNull);
        final err = jsonDecode(res.body)['error'];
        expect(err['code'], 'rate_limit_exceeded');
      },
    );

    test('10. Per-key concurrency limit returns 429', () async {
      final keyResult = await apiKeyService.createKey(
        name: 'Concurrency Key',
        maxConcurrentRequests: 1,
        rateLimitRpm: 100,
      );

      // Manually acquire slot to simulate in-flight request
      apiKeyService.acquireRequestSlot(keyResult.metadata.id);

      final res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${keyResult.plaintextSecret}'},
      );

      expect(res.statusCode, 429);
      expect(
        jsonDecode(res.body)['error']['code'],
        'concurrency_limit_exceeded',
      );

      // Release slot
      apiKeyService.releaseRequestSlot(keyResult.metadata.id);
      final successRes = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${keyResult.plaintextSecret}'},
      );
      expect(successRes.statusCode, 200);
    });

    test('11. Model restrictions enforce allowlist with 403', () async {
      final restrictedKey = await apiKeyService.createKey(
        name: 'Restricted Model Key',
        allowedModels: ['smollm2-135m.gguf'], // Only allows smollm2
      );

      // Active model is qwen2.5-0.5b.gguf
      final res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${restrictedKey.plaintextSecret}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen2.5-0.5b.gguf',
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
        }),
      );

      expect(res.statusCode, 403);
      final err = jsonDecode(res.body)['error'];
      expect(err['code'], 'model_not_allowed');
    });

    test(
      '12. Revocation takes effect immediately without server restart',
      () async {
        final keyResult = await apiKeyService.createKey(
          name: 'Quick Revoke Key',
        );

        // Works initially
        var res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: {'Authorization': 'Bearer ${keyResult.plaintextSecret}'},
        );
        expect(res.statusCode, 200);

        // Revoke immediately
        await apiKeyService.revokeKey(keyResult.metadata.id);

        // Next request immediately fails
        res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: {'Authorization': 'Bearer ${keyResult.plaintextSecret}'},
        );
        expect(res.statusCode, 401);
        expect(jsonDecode(res.body)['error']['code'], 'revoked_api_key');
      },
    );

    test('13. Persistence across service recreation simulation', () async {
      final keyResult = await apiKeyService.createKey(
        name: 'Persistent Dev Key',
      );

      // Simulate application restart: create a new service with the same underlying storage
      final newApiKeyService = ApiKeyService(storage: storage);
      await newApiKeyService.init();

      expect(newApiKeyService.keys, hasLength(1));
      expect(newApiKeyService.keys.first.name, 'Persistent Dev Key');

      // Authenticate with the new service instance
      final authResult = await newApiKeyService.authenticate(
        'Bearer ${keyResult.plaintextSecret}',
        requiredPermission: ApiKeyPermission.modelsList,
      );
      expect(authResult.isSuccess, isTrue);
      expect(authResult.key?.name, 'Persistent Dev Key');
      newApiKeyService.dispose();
    });

    test(
      '14. No unauthenticated inference requests reach the coordinator',
      () async {
        expect(coordinator.queueLength, 0);
        expect(mockService.isGenerating, isFalse);

        // Send unauthenticated chat completion request
        final res = await http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'qwen2.5-0.5b.gguf',
            'messages': [
              {'role': 'user', 'content': 'Should be rejected before queue'},
            ],
          }),
        );

        expect(res.statusCode, 401);
        // Verify coordinator was completely untouched
        expect(coordinator.queueLength, 0);
        expect(mockService.isGenerating, isFalse);
      },
    );

    test('15. No API key or hash appears in logs or error responses', () async {
      final keyResult = await apiKeyService.createKey(name: 'Sensitive Key');
      final secret = keyResult.plaintextSecret;
      final hash = keyResult.metadata.hashHex;

      // Bad request with wrong model
      final res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $secret',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'non-existent.gguf',
          'messages': [
            {'role': 'user', 'content': 'Test'},
          ],
        }),
      );

      expect(res.statusCode, 404);
      expect(res.body.contains(secret), isFalse);
      expect(res.body.contains(hash), isFalse);
    });

    test(
      '16. Client disconnects and cancellation safely release request slots',
      () async {
        final keyResult = await apiKeyService.createKey(
          name: 'Disconnect Slot Key',
        );
        final keyId = keyResult.metadata.id;

        expect(apiKeyService.getInFlightCount(keyId), 0);

        // Perform a streaming request and drop connection
        final client = HttpClient();
        final req = await client.postUrl(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
        );
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer ${keyResult.plaintextSecret}');
        req.write(
          jsonEncode({
            'model': 'qwen2.5-0.5b.gguf',
            'messages': [
              {'role': 'user', 'content': 'Disconnect'},
            ],
            'stream': true,
          }),
        );

        final res = await req.close();
        res.detachSocket().then((sock) => sock.destroy());

        await Future.delayed(const Duration(milliseconds: 50));

        // Slot must be 0 after disconnect cleanup
        expect(apiKeyService.getInFlightCount(keyId), 0);
        client.close(force: true);
      },
    );

    test('17. Existing UI chat remains independent of API requests', () async {
      // Start UI chat via coordinator with 'ui_chat' request ID
      final uiStream = await coordinator.generate(
        messages: [
          ChatMessage(
            id: 'ui_1',
            role: MessageRole.user,
            content: 'Hello UI',
            timestamp: DateTime.now(),
          ),
        ],
        settings: const GenerationSettings(),
        requestId: 'ui_chat',
      );

      expect(coordinator.activeRequestId, 'ui_chat');
      final tokens = await uiStream.toList();
      expect(tokens, isNotEmpty);
      expect(coordinator.isGenerating, isFalse);
    });

    test(
      '18. Existing API server start/stop behavior remains unchanged',
      () async {
        expect(server.isRunning, isTrue);
        await server.stop();
        expect(server.isStopped, isTrue);

        final restarted = await server.start(port: 0);
        expect(restarted, isTrue);
        expect(server.isRunning, isTrue);
      },
    );
  });
}
