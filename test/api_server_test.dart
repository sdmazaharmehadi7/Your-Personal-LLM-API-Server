import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

    // Emit tokens asynchronously
    Future.microtask(() async {
      final tokens = ['The', ' answer', ' is', ' 42.'];
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
  group('LocalApiServer Tests', () {
    late MockableInferenceService mockService;
    late InferenceCoordinator coordinator;
    late ApiKeyService apiKeyService;
    late LocalApiServer server;
    late String apiKeySecret;
    late Map<String, String> authHeaders;

    setUp(() async {
      mockService = MockableInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: mockService,
        maxQueueSize: 2,
      );
      apiKeyService = ApiKeyService(storage: InMemoryApiKeyStorage());
      await apiKeyService.init();
      final keyResult = await apiKeyService.createKey(
        name: 'Test Dev Key',
        rateLimitRpm: 100,
        maxConcurrentRequests: 10,
      );
      apiKeySecret = keyResult.plaintextSecret;
      authHeaders = {
        'Authorization': 'Bearer $apiKeySecret',
        'Content-Type': 'application/json',
      };
      server = LocalApiServer(
        coordinator: coordinator,
        apiKeyService: apiKeyService,
      );
    });

    tearDown(() async {
      await server.stop();
      server.dispose();
      coordinator.dispose();
      apiKeyService.dispose();
    });

    test(
      '1. Server starts on loopback 127.0.0.1 and reports actual port',
      () async {
        expect(server.isStopped, isTrue);
        final started = await server.start(
          port: 0,
        ); // port 0 assigns ephemeral port
        expect(started, isTrue);
        expect(server.isRunning, isTrue);
        expect(server.host, '127.0.0.1');
        expect(server.activePort, isNotNull);
        expect(server.activePort, greaterThan(0));
        expect(server.baseUrl, 'http://127.0.0.1:${server.activePort}');
      },
    );

    test('2. Server stops and releases its listening socket', () async {
      await server.start(port: 0);
      final port = server.activePort!;
      expect(server.isRunning, isTrue);

      await server.stop();
      expect(server.isStopped, isTrue);
      expect(server.activePort, isNull);
      expect(server.baseUrl, isEmpty);

      // Verify port can be re-bound immediately
      final newServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await newServer.close();
    });

    test(
      '3. Repeated start and stop operations are safe and idempotent',
      () async {
        expect(await server.start(port: 0), isTrue);
        final port = server.activePort;
        expect(await server.start(port: port), isTrue); // Repeated start
        expect(server.activePort, port);

        await server.stop();
        await server.stop(); // Repeated stop
        expect(server.isStopped, isTrue);
      },
    );

    test('4. Health endpoint works with and without loaded model', () async {
      await server.start(port: 0);

      // Without loaded model
      var res = await http.get(Uri.parse('${server.baseUrl}/health'));
      expect(res.statusCode, 200);
      var body = jsonDecode(res.body);
      expect(body['status'], 'ok');
      expect(body['model_loaded'], isFalse);
      expect(body['active_model'], isNull);
      expect(body['authenticated'], isTrue);
      expect(body['binding'], 'localhost_only');

      // With loaded model
      await coordinator.loadModel('/models/smollm2-135m.gguf');
      res = await http.get(Uri.parse('${server.baseUrl}/health'));
      expect(res.statusCode, 200);
      body = jsonDecode(res.body);
      expect(body['model_loaded'], isTrue);
      expect(body['active_model'], 'smollm2-135m.gguf');
    });

    test('5. Model listing reports the correct active model', () async {
      await server.start(port: 0);

      // No model loaded
      var res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: authHeaders,
      );
      expect(res.statusCode, 200);
      var body = jsonDecode(res.body);
      expect(body['object'], 'list');
      expect(body['data'], isEmpty);

      // Load model
      await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');
      res = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: authHeaders,
      );
      expect(res.statusCode, 200);
      body = jsonDecode(res.body);
      expect(body['object'], 'list');
      expect(body['data'], hasLength(1));
      expect(body['data'][0]['id'], 'qwen2.5-0.5b.gguf');
      expect(body['data'][0]['object'], 'model');
    });

    test('6. Valid non-streaming chat request returns expected OpenAI JSON structure', () async {
      await server.start(port: 0);
      await coordinator.loadModel('/models/smollm2-135m.gguf');

      final res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: authHeaders,
        body: jsonEncode({
          'model': 'smollm2-135m.gguf',
          'messages': [
            {'role': 'system', 'content': 'You are a helpful assistant.'},
            {'role': 'user', 'content': 'What is the answer?'},
          ],
          'temperature': 0.7,
          'stream': false,
        }),
      );

      expect(res.statusCode, 200);
      final data = jsonDecode(res.body);
      expect(data['object'], 'chat.completion');
      expect(data['model'], 'smollm2-135m.gguf');
      expect(data['choices'], hasLength(1));
      expect(data['choices'][0]['message']['role'], 'assistant');
      expect(data['choices'][0]['message']['content'], 'The answer is 42.');
      expect(data['choices'][0]['finish_reason'], 'stop');
      expect(data['usage'], isNotNull);
      expect(data['usage']['completion_tokens'], 4);
    });

    test(
      '7. Valid streaming request produces correctly formatted SSE and [DONE]',
      () async {
        await server.start(port: 0);
        await coordinator.loadModel('/models/smollm2-135m.gguf');

        final request = http.Request(
          'POST',
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
        );
        request.headers.addAll(authHeaders);
        request.body = jsonEncode({
          'model': 'smollm2-135m.gguf',
          'messages': [
            {'role': 'user', 'content': 'Count to 3.'},
          ],
          'stream': true,
        });

        final streamedResponse = await request.send();
        expect(streamedResponse.statusCode, 200);
        expect(
          streamedResponse.headers['content-type'],
          contains('text/event-stream'),
        );

        final sseLines = await streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.startsWith('data: '))
            .toList();

        expect(sseLines, isNotEmpty);
        expect(sseLines.last, 'data: [DONE]');

        // First chunk has role
        final firstChunk = jsonDecode(sseLines.first.substring(6));
        expect(firstChunk['object'], 'chat.completion.chunk');
        expect(firstChunk['choices'][0]['delta']['role'], 'assistant');

        // Subsequent chunks have content
        final contentChunks = sseLines
            .sublist(1, sseLines.length - 2)
            .map(
              (l) =>
                  jsonDecode(l.substring(6))['choices'][0]['delta']['content']
                      as String,
            )
            .join('');
        expect(contentChunks, 'The answer is 42.');
      },
    );

    test(
      '8. Malformed JSON and invalid messages return appropriate 400 errors',
      () async {
        await server.start(port: 0);
        await coordinator.loadModel('/models/test.gguf');

        // Syntax error in JSON
        var res = await http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: '{"invalid": json syntax',
        );
        expect(res.statusCode, 400);
        var err = jsonDecode(res.body)['error'];
        expect(err['code'], 'invalid_json');

        // Empty messages array
        res = await http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({'model': 'test.gguf', 'messages': []}),
        );
        expect(res.statusCode, 400);
        err = jsonDecode(res.body)['error'];
        expect(err['code'], 'invalid_messages');

        // Unsupported role
        res = await http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({
            'model': 'test.gguf',
            'messages': [
              {'role': 'hacker', 'content': 'hi'},
            ],
          }),
        );
        expect(res.statusCode, 400);
        err = jsonDecode(res.body)['error'];
        expect(err['code'], 'unsupported_role');
      },
    );

    test('9. Unknown model IDs are rejected with 404', () async {
      await server.start(port: 0);
      await coordinator.loadModel('/models/active-model.gguf');

      final res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: authHeaders,
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        }),
      );

      expect(res.statusCode, 404);
      final err = jsonDecode(res.body)['error'];
      expect(err['code'], 'model_not_found');
      expect(err['message'], contains('active-model.gguf'));
    });

    test(
      '10. Requests without loaded model fail predictably with 503',
      () async {
        await server.start(port: 0);
        // No model loaded in coordinator

        final res = await http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({
            'model': 'any-model.gguf',
            'messages': [
              {'role': 'user', 'content': 'Hello'},
            ],
          }),
        );

        expect(res.statusCode, 503);
        final err = jsonDecode(res.body)['error'];
        expect(err['code'], 'model_not_loaded');
      },
    );

    test('11. Queue-full errors map to safe 429 HTTP responses', () async {
      await server.start(port: 0);
      await coordinator.loadModel('/models/test.gguf');

      // Submit 4 requests concurrently
      final client = HttpClient();
      final futures = <Future<HttpClientResponse>>[];

      for (int i = 0; i < 4; i++) {
        final reqFuture = client
            .postUrl(Uri.parse('${server.baseUrl}/v1/chat/completions'))
            .then((req) {
              req.headers.contentType = ContentType.json;
              req.headers.set('Authorization', 'Bearer $apiKeySecret');
              req.write(
                jsonEncode({
                  'model': 'test.gguf',
                  'messages': [
                    {'role': 'user', 'content': 'Query $i'},
                  ],
                  'stream': false,
                }),
              );
              return req.close();
            });
        futures.add(reqFuture);
      }

      final responses = await Future.wait(futures);
      final statusCodes = responses.map((r) => r.statusCode).toList();

      // At least one request beyond the queue limit must return 429
      expect(statusCodes, contains(429));
      client.close(force: true);
    });

    test(
      '12. Client disconnects and cancellation clean up resources',
      () async {
        await server.start(port: 0);
        await coordinator.loadModel('/models/test.gguf');

        // Initiate connection then immediately close socket
        final client = HttpClient();
        final req = await client.postUrl(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
        );
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $apiKeySecret');
        req.write(
          jsonEncode({
            'model': 'test.gguf',
            'messages': [
              {'role': 'user', 'content': 'Abort me'},
            ],
            'stream': true,
          }),
        );

        final res = await req.close();
        // Drop connection by destroying socket
        res.detachSocket().then((sock) => sock.destroy());

        // Give event loop a beat to process disconnect
        await Future.delayed(const Duration(milliseconds: 50));

        expect(coordinator.queueLength, 0);
        client.close(force: true);
      },
    );

    test(
      '13. Multiple HTTP requests do not execute native inference concurrently',
      () async {
        await server.start(port: 0);
        await coordinator.loadModel('/models/test.gguf');

        final results = <String>[];
        final req1 = http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({
            'model': 'test.gguf',
            'messages': [
              {'role': 'user', 'content': 'Task 1'},
            ],
          }),
        );

        final req2 = http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({
            'model': 'test.gguf',
            'messages': [
              {'role': 'user', 'content': 'Task 2'},
            ],
          }),
        );

        final responses = await Future.wait([req1, req2]);
        for (final r in responses) {
          expect(r.statusCode, 200);
          results.add(jsonDecode(r.body)['choices'][0]['message']['content']);
        }

        expect(results, ['The answer is 42.', 'The answer is 42.']);
      },
    );

    test(
      '14. No HTTP request accidentally cancels the UI ui_chat generation',
      () async {
        await server.start(port: 0);
        await coordinator.loadModel('/models/test.gguf');

        // Start UI generation with 'ui_chat' requestId
        final uiStream = await coordinator.generate(
          messages: [
            ChatMessage(
              id: 'ui_msg',
              role: MessageRole.user,
              content: 'UI message',
              timestamp: DateTime.now(),
            ),
          ],
          settings: const GenerationSettings(),
          requestId: 'ui_chat',
        );

        expect(coordinator.activeRequestId, 'ui_chat');

        // While UI chat is generating, submit an HTTP request
        final httpReq = http.post(
          Uri.parse('${server.baseUrl}/v1/chat/completions'),
          headers: authHeaders,
          body: jsonEncode({
            'model': 'test.gguf',
            'messages': [
              {'role': 'user', 'content': 'HTTP query'},
            ],
          }),
        );

        // Allow async HTTP request to reach coordinator queue
        for (int i = 0; i < 50 && coordinator.queueLength == 0; i++) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // Verify HTTP request has been queued behind ui_chat
        expect(coordinator.queueLength, 1);
        expect(coordinator.activeRequestId, 'ui_chat');

        // UI chat completes
        final uiTokens = await uiStream.toList();
        expect(uiTokens, isNotEmpty);

        // HTTP request now executes and succeeds
        final httpRes = await httpReq;
        expect(httpRes.statusCode, 200);
        expect(
          jsonDecode(httpRes.body)['choices'][0]['message']['content'],
          'The answer is 42.',
        );
      },
    );

    test('15. Oversized bodies, unsupported paths, and unsupported methods are handled correctly', () async {
      await server.start(port: 0);

      // Unsupported path
      var res = await http.get(Uri.parse('${server.baseUrl}/unknown/route'));
      expect(res.statusCode, 404);
      expect(jsonDecode(res.body)['error']['code'], 'resource_not_found');

      // Unsupported method (e.g. DELETE on /health)
      res = await http.delete(Uri.parse('${server.baseUrl}/health'));
      expect(res.statusCode, 404);

      // Oversized body (> 2MB)
      final largeContent = 'a' * (LocalApiServer.maxRequestBodyBytes + 1024);
      res = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: authHeaders,
        body: jsonEncode({
          'model': 'test.gguf',
          'messages': [
            {'role': 'user', 'content': largeContent},
          ],
        }),
      );
      expect(res.statusCode, 413);
      expect(jsonDecode(res.body)['error']['code'], 'request_too_large');
    });

    test(
      '16. Stopping the server does not unload model or delete user data',
      () async {
        await coordinator.loadModel('/models/persistent.gguf');
        expect(coordinator.isLoaded, isTrue);

        await server.start(port: 0);
        expect(server.isRunning, isTrue);

        await server.stop();
        expect(server.isStopped, isTrue);

        // Model must remain loaded in coordinator
        expect(coordinator.isLoaded, isTrue);
        expect(coordinator.currentModelName, 'persistent.gguf');
      },
    );

    test('17. Local-only mode binds strictly to loopback and refuses LAN IP', () async {
      final started = await server.start(
        port: 0,
        allowExternalConnections: false,
      );
      expect(started, isTrue);
      expect(server.allowExternalConnections, isFalse);
      expect(server.host, '127.0.0.1');
      expect(server.bindAddress, InternetAddress.loopbackIPv4);
      expect(server.baseUrl, 'http://127.0.0.1:${server.activePort}');

      final lanIp = await LocalApiServer.getPrimaryLanIp();
      if (lanIp != null && lanIp != '127.0.0.1') {
        final client = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 500);
        try {
          final req = await client.getUrl(
            Uri.parse('http://$lanIp:${server.activePort}/health'),
          );
          await req.close();
          fail(
            'Connection to LAN IP should have been refused in local-only mode',
          );
        } catch (e) {
          expect(e, isA<SocketException>());
        } finally {
          client.close();
        }
      }
    });

    test('18. LAN external connections mode binds to 0.0.0.0 and displays actual LAN IP', () async {
      final started = await server.start(
        port: 0,
        allowExternalConnections: true,
      );
      expect(started, isTrue);
      expect(server.allowExternalConnections, isTrue);
      expect(server.bindAddress, InternetAddress.anyIPv4);

      final lanIp = await LocalApiServer.getPrimaryLanIp();
      if (lanIp != null) {
        expect(server.lanIp, equals(lanIp));
        expect(server.host, equals(lanIp));
        expect(server.baseUrl, 'http://$lanIp:${server.activePort}');
      }
      expect(server.baseUrl, isNot(contains('0.0.0.0')));

      // Can connect via loopback
      final loopbackRes = await http.get(
        Uri.parse('http://127.0.0.1:${server.activePort}/health'),
      );
      expect(loopbackRes.statusCode, 200);

      // Can connect via LAN IP
      if (lanIp != null && lanIp != '127.0.0.1') {
        final lanRes = await http.get(
          Uri.parse('http://$lanIp:${server.activePort}/health'),
        );
        expect(lanRes.statusCode, 200);
      }
    });

    test('19. Dynamic toggling of external connections restarts server safely with correct binding', () async {
      await server.start(port: 0, allowExternalConnections: false);
      final initialPort = server.activePort!;
      expect(server.bindAddress, InternetAddress.loopbackIPv4);

      // Toggle to true while running
      final switchedToLan = await server.setAllowExternalConnections(true);
      expect(switchedToLan, isTrue);
      expect(server.isRunning, isTrue);
      expect(server.allowExternalConnections, isTrue);
      expect(server.bindAddress, InternetAddress.anyIPv4);
      expect(server.activePort, equals(initialPort));

      // Toggle back to false while running
      final switchedToLocal = await server.setAllowExternalConnections(false);
      expect(switchedToLocal, isTrue);
      expect(server.isRunning, isTrue);
      expect(server.allowExternalConnections, isFalse);
      expect(server.bindAddress, InternetAddress.loopbackIPv4);
      expect(server.activePort, equals(initialPort));
    });

    test('20. LAN requests strictly enforce API-key authentication and permissions', () async {
      await coordinator.loadModel('/models/lan_test.gguf');
      await server.start(port: 0, allowExternalConnections: true);

      final targetHost = server.host; // Actual LAN IP or fallback
      final modelsUrl = Uri.parse(
        'http://$targetHost:${server.activePort}/v1/models',
      );

      // 1. Missing Authorization header returns 401
      final unauthRes = await http.get(modelsUrl);
      expect(unauthRes.statusCode, 401);
      expect(
        jsonDecode(unauthRes.body)['error']['code'],
        'missing_authorization_header',
      );

      // 2. Invalid API key returns 401
      final badKeyRes = await http.get(
        modelsUrl,
        headers: {'Authorization': 'Bearer sk-sov-invalid-key-here'},
      );
      expect(badKeyRes.statusCode, 401);
      expect(jsonDecode(badKeyRes.body)['error']['code'], 'invalid_api_key');

      // 3. Valid API key succeeds
      final validRes = await http.get(
        modelsUrl,
        headers: {'Authorization': 'Bearer $apiKeySecret'},
      );
      expect(validRes.statusCode, 200);
      final modelsBody = jsonDecode(validRes.body);
      expect(modelsBody['data'], isNotEmpty);
    });

    test('21. Keyless localhost mode allows local Mac requests without an API key (like Ollama)', () async {
      await coordinator.loadModel('/models/ollama_test.gguf');
      server.setAllowKeylessLocalhost(true);
      await server.start(port: 0);

      // 1. GET /v1/models with NO Authorization header succeeds with 200
      final modelsRes = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
      );
      expect(modelsRes.statusCode, 200);
      final modelsJson = jsonDecode(modelsRes.body);
      expect(modelsJson['data'], hasLength(1));

      // 2. POST /v1/chat/completions with NO Authorization header succeeds with 200
      final chatRes = await http.post(
        Uri.parse('${server.baseUrl}/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'local',
          'messages': [
            {'role': 'user', 'content': 'Hello from Mac without API key'},
          ],
        }),
      );
      expect(chatRes.statusCode, 200);
      final chatJson = jsonDecode(chatRes.body);
      expect(chatJson['choices'][0]['message']['content'], contains('42'));

      // 3. Requests with 'Bearer local' or 'Bearer ollama' also succeed
      final localBearerRes = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'Authorization': 'Bearer ollama'},
      );
      expect(localBearerRes.statusCode, 200);
    });

    test('22. Keyless localhost mode still rejects requests carrying remote tunnel headers', () async {
      server.setAllowKeylessLocalhost(true);
      await server.start(port: 0);

      // Simulating a request arriving from Cloudflare tunnel without API key
      final tunnelRes = await http.get(
        Uri.parse('${server.baseUrl}/v1/models'),
        headers: {'cf-connecting-ip': '203.0.113.195'},
      );
      expect(tunnelRes.statusCode, 401);
      expect(
        jsonDecode(tunnelRes.body)['error']['code'],
        'missing_authorization_header',
      );
    });
  });
}
