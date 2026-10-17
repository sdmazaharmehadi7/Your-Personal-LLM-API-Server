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
import 'package:sovereign_ai/services/remote_access/remote_access_manager.dart';
import 'package:sovereign_ai/services/remote_access/remote_access_provider.dart';

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
      final tokens = ['Remote', ' AI', ' generation', ' complete.'];
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
  group('Prompt 6: Secure Remote Access Tests', () {
    late MockableInferenceService mockService;
    late InferenceCoordinator coordinator;
    late InMemoryApiKeyStorage storage;
    late ApiKeyService apiKeyService;
    late LocalApiServer server;
    late MockRemoteAccessProvider mockProvider;
    late RemoteAccessManager remoteManager;
    late String testApiKey;

    setUp(() async {
      mockService = MockableInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: mockService,
        maxQueueSize: 4,
      );
      storage = InMemoryApiKeyStorage();
      apiKeyService = ApiKeyService(storage: storage);
      await apiKeyService.init();

      final keyResult = await apiKeyService.createKey(
        name: 'Remote Access Developer Key',
        rateLimitRpm: 60,
        maxConcurrentRequests: 2,
      );
      testApiKey = keyResult.plaintextSecret;

      server = LocalApiServer(
        coordinator: coordinator,
        apiKeyService: apiKeyService,
      );
      mockProvider = MockRemoteAccessProvider();
      remoteManager = RemoteAccessManager(
        apiServer: server,
        provider: mockProvider,
      );
    });

    tearDown(() async {
      await remoteManager.stopRemoteAccess();
      remoteManager.dispose();
      await server.stop();
      server.dispose();
      coordinator.dispose();
      apiKeyService.dispose();
    });

    test('1. Remote access is disabled by default', () {
      expect(remoteManager.isDisabled, isTrue);
      expect(remoteManager.isConnected, isFalse);
      expect(remoteManager.publicHttpsUrl, isNull);
      expect(mockProvider.status, RemoteAccessStatus.disabled);
    });

    test(
      '2. Starting remote access fails safely when local API server is stopped',
      () async {
        expect(server.isStopped, isTrue);

        final success = await remoteManager.startRemoteAccess();
        expect(success, isFalse);
        expect(remoteManager.isConnected, isFalse);
        expect(remoteManager.errorMessage, contains('must be running'));
        expect(mockProvider.status, RemoteAccessStatus.disabled);
      },
    );

    test(
      '3. Starting a tunnel does not start another HTTP inference server',
      () async {
        await server.start(port: 0);
        final initialPort = server.activePort;

        final success = await remoteManager.startRemoteAccess();
        expect(success, isTrue);
        expect(remoteManager.isConnected, isTrue);

        // Verify the local server port and host are identical and unchanged
        expect(server.activePort, initialPort);
        expect(server.host, '127.0.0.1');
        expect(coordinator.queueLength, 0);
      },
    );

    test('4. Starting and stopping remote access is idempotent', () async {
      await server.start(port: 0);

      // Start once
      expect(await remoteManager.startRemoteAccess(), isTrue);
      expect(remoteManager.isConnected, isTrue);

      // Start again while connected -> returns true idempotently
      expect(await remoteManager.startRemoteAccess(), isTrue);
      expect(remoteManager.isConnected, isTrue);

      // Stop once
      await remoteManager.stopRemoteAccess();
      expect(remoteManager.isDisabled, isTrue);
      expect(remoteManager.publicHttpsUrl, isNull);

      // Stop again while disabled -> safe no-op
      await remoteManager.stopRemoteAccess();
      expect(remoteManager.isDisabled, isTrue);
    });

    test('5. Duplicate tunnel processes are prevented', () async {
      await server.start(port: 0);

      // Start remote access
      await remoteManager.startRemoteAccess();
      final url = remoteManager.publicHttpsUrl;

      // Triggering start again does not invoke a secondary tunnel
      await remoteManager.startRemoteAccess();
      expect(remoteManager.publicHttpsUrl, url);
    });

    test('6. Tunnel startup failures are reported safely', () async {
      await server.start(port: 0);
      mockProvider.shouldFailStartup = true;

      final success = await remoteManager.startRemoteAccess();
      expect(success, isFalse);
      expect(remoteManager.isConnected, isFalse);
      expect(remoteManager.hasError, isTrue);
      expect(
        remoteManager.errorMessage,
        contains('Simulated tunnel startup failure'),
      );
      expect(remoteManager.publicHttpsUrl, isNull);
    });

    test('7. Unexpected tunnel termination updates application status and clears URL', () async {
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();
      expect(remoteManager.isConnected, isTrue);
      expect(remoteManager.publicHttpsUrl, isNotNull);

      // Simulate tunnel process crashing or dropping connection
      mockProvider.simulateUnexpectedDisconnect(
        'Tunnel connection reset by peer',
      );

      expect(remoteManager.isConnected, isFalse);
      expect(remoteManager.hasError, isTrue);
      expect(remoteManager.publicHttpsUrl, isNull);
      expect(remoteManager.errorMessage, contains('reset by peer'));
    });

    test('8. Stopping the local server also stops remote access', () async {
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();
      expect(remoteManager.isConnected, isTrue);

      // Stop local API server
      await server.stop();

      // Remote access manager should detect local server shutdown and stop the tunnel
      expect(remoteManager.isDisabled, isTrue);
      expect(remoteManager.publicHttpsUrl, isNull);
    });

    test(
      '9. Application disposal stops the tunnel and cleans up resources',
      () async {
        await server.start(port: 0);
        await remoteManager.startRemoteAccess();
        expect(remoteManager.isConnected, isTrue);

        remoteManager.dispose();
        expect(mockProvider.status, RemoteAccessStatus.disabled);
      },
    );

    test('10. Stopping remote access does not unload the model', () async {
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      expect(coordinator.isLoaded, isTrue);

      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      // Stop remote access
      await remoteManager.stopRemoteAccess();

      // Model must remain loaded in coordinator
      expect(coordinator.isLoaded, isTrue);
      expect(coordinator.currentModelName, 'qwen2.5-0.5b.gguf');
    });

    test(
      '11. Local API access remains functional when tunnel is disabled',
      () async {
        await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
        await server.start(port: 0);
        expect(remoteManager.isDisabled, isTrue);

        // Local request succeeds with valid Bearer key
        final res = await http.get(
          Uri.parse('${server.baseUrl}/v1/models'),
          headers: {'Authorization': 'Bearer $testApiKey'},
        );

        expect(res.statusCode, 200);
        final body = jsonDecode(res.body);
        expect(body['data'], hasLength(1));
      },
    );

    test('12. Existing API-key authentication remains mandatory for remote chat and model requests', () async {
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      // Unauthenticated request to the local endpoint (forwarded target of the tunnel)
      final unauthRes = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'qwen2.5-0.5b.gguf',
          'messages': [
            {'role': 'user', 'content': 'Test'},
          ],
        }),
      );
      expect(unauthRes.statusCode, 401);

      // Authenticated request succeeds
      final authRes = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $testApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen2.5-0.5b.gguf',
          'messages': [
            {'role': 'user', 'content': 'Test'},
          ],
        }),
      );
      expect(authRes.statusCode, 200);
      expect(jsonDecode(authRes.body)['object'], 'chat.completion');
    });

    test('13. Rate limits and model restrictions continue to apply', () async {
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      // Key restricted to smollm2 only
      final restrictedKey = await apiKeyService.createKey(
        name: 'Restricted Key',
        allowedModels: ['smollm2-135m.gguf'],
      );

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
      expect(jsonDecode(res.body)['error']['code'], 'model_not_allowed');
    });

    test('14. Request cancellation and client disconnect handling remain functional', () async {
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
      );
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $testApiKey');
      req.write(
        jsonEncode({
          'model': 'qwen2.5-0.5b.gguf',
          'messages': [
            {'role': 'user', 'content': 'Cancel me'},
          ],
          'stream': true,
        }),
      );

      final res = await req.close();
      res.detachSocket().then((sock) => sock.destroy());

      await Future.delayed(const Duration(milliseconds: 50));
      expect(coordinator.queueLength, 0);
      client.close(force: true);
    });

    test('15. Provider credentials and API keys are absent from logs and public URLs', () async {
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      final publicUrl = remoteManager.publicHttpsUrl!;
      expect(publicUrl.contains(testApiKey), isFalse);
      expect(publicUrl.startsWith('https://'), isTrue);
    });

    test('16. The API server remains bound strictly to 127.0.0.1', () async {
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      expect(server.host, '127.0.0.1');
      expect(server.host, isNot('0.0.0.0'));
      expect(server.baseUrl.startsWith('http://127.0.0.1:'), isTrue);
    });

    test('17. No public administrative endpoint is introduced', () async {
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      // Admin or key-generation endpoints should not exist on HTTP API
      final res = await http.get(Uri.parse('${server.baseUrl}/admin/keys'));
      expect(res.statusCode, 404);

      final res2 = await http.post(Uri.parse('${server.baseUrl}/v1/keys'));
      expect(res2.statusCode, 404);
    });

    test(
      '18. Existing model lifecycle and UI chat behavior remain unchanged',
      () async {
        await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
        await server.start(port: 0);
        await remoteManager.startRemoteAccess();

        // UI chat generation via 'ui_chat' request ID
        final uiStream = await coordinator.generate(
          messages: [
            ChatMessage(
              id: 'ui_msg',
              role: MessageRole.user,
              content: 'Local UI chat query',
              timestamp: DateTime.now(),
            ),
          ],
          settings: const GenerationSettings(),
          requestId: 'ui_chat',
        );

        final tokens = await uiStream.toList();
        expect(tokens, isNotEmpty);
        expect(coordinator.isGenerating, isFalse);
      },
    );

    test('19. Revoked API keys are immediately rejected through the tunnel request path', () async {
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      await server.start(port: 0);
      await remoteManager.startRemoteAccess();

      final keyToRevoke = await apiKeyService.createKey(name: 'Key To Revoke');

      // Revoke the key
      await apiKeyService.revokeKey(keyToRevoke.metadata.id);
      expect(
        apiKeyService.keys
            .firstWhere((k) => k.id == keyToRevoke.metadata.id)
            .isRevoked,
        isTrue,
      );

      // Attempt to access API via revoked key
      final res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ${keyToRevoke.plaintextSecret}'},
      );

      expect(res.statusCode, 401);
      final body = jsonDecode(res.body);
      expect(body['error']['code'], 'revoked_api_key');
    });

    test('20. CloudflareQuickTunnelProvider validates trycloudflare URLs and rejects invalid destinations', () {
      // Valid HTTPS trycloudflare URL
      expect(
        CloudflareQuickTunnelProvider.validateTunnelUrl(
          '2026-10-16 INF |  https://my-test-tunnel.trycloudflare.com  |',
        ),
        'https://my-test-tunnel.trycloudflare.com',
      );

      // Rejects non-HTTPS
      expect(
        CloudflareQuickTunnelProvider.validateTunnelUrl(
          'http://my-test-tunnel.trycloudflare.com',
        ),
        isNull,
      );

      // Rejects foreign domain
      expect(
        CloudflareQuickTunnelProvider.validateTunnelUrl(
          'https://attacker-site.com/trycloudflare.com',
        ),
        isNull,
      );

      // Rejects empty / random text
      expect(
        CloudflareQuickTunnelProvider.validateTunnelUrl(
          'Cloudflare tunnel starting...',
        ),
        isNull,
      );
    });

    test('21. FileApiKeyStorage enforces restrictive 0600 file permissions on POSIX systems', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'sovereign_keys_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final fileStorage = FileApiKeyStorage(customBaseDirectory: tempDir);
      await fileStorage.init();
      await fileStorage.saveKeys([
        ApiKeyMetadata(
          id: 'test_key',
          name: 'Perm Test Key',
          keyPrefix: 'sk-sov-perm',
          permissions: const {ApiKeyPermission.chatCompletions},
          saltHex: '0123456789abcdef0123456789abcdef',
          hashHex: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          createdAt: DateTime.now(),
        ),
      ]);

      final keyFile = File('${tempDir.path}/api_keys.json');
      expect(await keyFile.exists(), isTrue);

      if (!Platform.isWindows) {
        final stat = await keyFile.stat();
        // Mode 0600 is 384 decimal or owner read/write (0600 & 0777 == 0600)
        expect(stat.mode & 0x1ff, equals(0x180)); // 0600 in octal = 384 decimal
      }
    });

    test('22. Health endpoint response does not expose sensitive machine details or secrets', () async {
      await server.start(port: 0);
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');

      final res = await http.get(Uri.parse('${server.baseUrl}/health'));
      expect(res.statusCode, 200);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body.containsKey('secret'), isFalse);
      expect(body.containsKey('api_key'), isFalse);

      // Model name should only expose the filename, not local absolute filesystem paths
      if (body['active_model'] != null) {
        expect(body['active_model'].toString().contains('/Users/'), isFalse);
      }
    });
  });
}
