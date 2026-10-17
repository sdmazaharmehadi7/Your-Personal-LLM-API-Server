import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/api_server/api_key_service.dart';
import 'package:sovereign_ai/services/api_server/local_api_server.dart';
import 'package:sovereign_ai/services/inference_coordinator.dart';
import 'package:sovereign_ai/services/inference_service.dart';
import 'package:sovereign_ai/services/remote_access/remote_access_manager.dart';
import 'package:sovereign_ai/services/remote_access/remote_access_provider.dart';
import 'package:sovereign_ai/services/storage_service.dart';
import 'package:sovereign_ai/state/app_scope.dart';
import 'package:sovereign_ai/state/chat_state.dart';
import 'package:sovereign_ai/state/model_state.dart';
import 'package:sovereign_ai/state/settings_state.dart';
import 'package:sovereign_ai/ui/settings/sample_endpoints_screen.dart';
import 'package:sovereign_ai/ui/settings/settings_screen.dart';

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
      final tokens = ['Sovereign', ' AI', ' operational.'];
      for (final t in tokens) {
        if (controller.isClosed) break;
        controller.add(t);
        await Future.delayed(const Duration(milliseconds: 2));
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

Widget buildTestApp({
  required LocalApiServer apiServer,
  required ApiKeyService apiKeyService,
  required RemoteAccessManager remoteAccessManager,
  required ModelState modelState,
  required SettingsState settingsState,
  required ChatState chatState,
  required IStorageService storageService,
  required Widget child,
}) {
  return AppScope(
    apiServer: apiServer,
    apiKeyService: apiKeyService,
    remoteAccessManager: remoteAccessManager,
    modelState: modelState,
    settingsState: settingsState,
    chatState: chatState,
    storageService: storageService,
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Sample Endpoints & UI Enhancements Tests', () {
    late MockableInferenceService mockService;
    late InferenceCoordinator coordinator;
    late InMemoryApiKeyStorage apiKeyStorage;
    late ApiKeyService apiKeyService;
    late LocalApiServer apiServer;
    late MockRemoteAccessProvider mockProvider;
    late RemoteAccessManager remoteManager;
    late InMemoryStorageService storageService;
    late SettingsState settingsState;
    late ModelState modelState;
    late ChatState chatState;

    setUp(() async {
      mockService = MockableInferenceService();
      coordinator = InferenceCoordinator(
        inferenceService: mockService,
        maxQueueSize: 4,
      );
      apiKeyStorage = InMemoryApiKeyStorage();
      apiKeyService = ApiKeyService(storage: apiKeyStorage);
      await apiKeyService.init();

      apiServer = LocalApiServer(
        coordinator: coordinator,
        apiKeyService: apiKeyService,
      );
      mockProvider = MockRemoteAccessProvider();
      remoteManager = RemoteAccessManager(
        apiServer: apiServer,
        provider: mockProvider,
      );

      storageService = InMemoryStorageService();
      await storageService.init();
      settingsState = SettingsState(storageService: storageService);
      await settingsState.init();
      modelState = ModelState(
        storageService: storageService,
        coordinator: coordinator,
      );
      await modelState.init();
      chatState = ChatState(
        storageService: storageService,
        modelState: modelState,
      );
      await chatState.init();
    });

    tearDown(() async {
      await remoteManager.stopRemoteAccess();
      remoteManager.dispose();
      await apiServer.stop();
      apiServer.dispose();
      coordinator.dispose();
      apiKeyService.dispose();
    });

    testWidgets(
      '1. Settings screen displays Local API Server section matching reference',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildTestApp(
            apiServer: apiServer,
            apiKeyService: apiKeyService,
            remoteAccessManager: remoteManager,
            modelState: modelState,
            settingsState: settingsState,
            chatState: chatState,
            storageService: storageService,
            child: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Verify headings and elements from Screenshot 1
        expect(find.text('Local API Server'), findsOneWidget);
        expect(
          find.text(
            'Expose the loaded model to OpenAI-compatible local clients.',
          ),
          findsOneWidget,
        );
        expect(find.text('Local API server'), findsOneWidget);
        expect(find.text('Allow External Connections'), findsOneWidget);
        expect(
          find.text('Anyone on your network can access your loaded model.'),
          findsOneWidget,
        );
        expect(find.text('No model loaded'), findsOneWidget);
        expect(find.text('Sample Endpoints & Testing'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(find.text('Storage'), findsOneWidget);
        expect(find.text('Danger Zone'), findsOneWidget);
        expect(find.text('Delete All Chats'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Toggling server switch starts and stops the real LocalApiServer',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildTestApp(
            apiServer: apiServer,
            apiKeyService: apiKeyService,
            remoteAccessManager: remoteManager,
            modelState: modelState,
            settingsState: settingsState,
            chatState: chatState,
            storageService: storageService,
            child: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(apiServer.isRunning, isFalse);

        // Tap server toggle switch
        final switches = find.byType(Switch);
        expect(switches, findsWidgets);
        await tester.tap(switches.first);
        await tester.pumpAndSettle();

        expect(apiServer.isRunning, isTrue);

        // Tap toggle switch again to stop
        await tester.tap(switches.first);
        await tester.pumpAndSettle();

        expect(apiServer.isRunning, isFalse);
      },
    );

    testWidgets('3. Port validation rejects invalid port numbers', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          apiServer: apiServer,
          apiKeyService: apiKeyService,
          remoteAccessManager: remoteManager,
          modelState: modelState,
          settingsState: settingsState,
          chatState: chatState,
          storageService: storageService,
          child: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find port text field by key
      final portField = find.byKey(const Key('api_server_port_field'));
      expect(portField, findsOneWidget);

      // Enter invalid port
      await tester.enterText(portField, '999999');
      await tester.pumpAndSettle();
      expect(find.text('Invalid port (1 - 65535)'), findsOneWidget);

      // Enter valid port
      await tester.enterText(portField, '4891');
      await tester.pumpAndSettle();
      expect(find.text('Invalid port (1 - 65535)'), findsNothing);
      expect(apiServer.configuredPort, 4891);
    });

    testWidgets('4. Navigation to Sample Endpoints screen works smoothly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          apiServer: apiServer,
          apiKeyService: apiKeyService,
          remoteAccessManager: remoteManager,
          modelState: modelState,
          settingsState: settingsState,
          chatState: chatState,
          storageService: storageService,
          child: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Sample Endpoints & Testing button
      final sampleButton = find.text('Sample Endpoints & Testing');
      expect(sampleButton, findsOneWidget);
      await tester.tap(sampleButton);
      await tester.pumpAndSettle();

      // Verify we arrived on Sample Endpoints screen
      expect(find.text('Sample Endpoints'), findsOneWidget);
      expect(find.text('How to Access'), findsOneWidget);
      expect(find.text('/v1/models'), findsOneWidget);
      expect(find.text('/v1/chat/completions'), findsOneWidget);
      expect(find.text('Server Status: Stopped'), findsOneWidget);

      // Tap back button
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Verify returned to Settings
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
      '5. Sample Endpoints displays Running status and tests GET /v1/models',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.runAsync(() async {
          await apiServer.start(port: 0);
        });
        expect(apiServer.isRunning, isTrue);

        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('/v1/models')) {
            return http.Response(
              jsonEncode({
                'object': 'list',
                'data': [
                  {'id': 'qwen2.5-0.5b.gguf', 'object': 'model'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          buildTestApp(
            apiServer: apiServer,
            apiKeyService: apiKeyService,
            remoteAccessManager: remoteManager,
            modelState: modelState,
            settingsState: settingsState,
            chatState: chatState,
            storageService: storageService,
            child: SampleEndpointsScreen(httpClient: mockClient),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Server Status: Running'), findsOneWidget);
        expect(find.textContaining('http://127.0.0.1:'), findsWidgets);

        // Find Test buttons
        final testButtons = find.text('Test');
        expect(testButtons, findsNWidgets(2));

        // Test GET /v1/models (first button)
        await tester.tap(testButtons.first);
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        // Check HTTP 200 OK result
        expect(find.textContaining('HTTP 200 OK'), findsOneWidget);
        expect(find.textContaining('"object": "list"'), findsOneWidget);
        expect(find.textContaining('qwen2.5-0.5b.gguf'), findsOneWidget);

        await tester.runAsync(() async {
          await apiServer.stop();
        });
      },
    );

    testWidgets(
      '6. Sample Endpoints allows real testing of POST /v1/chat/completions when model loaded',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.runAsync(() async {
          await apiServer.start(port: 0);
        });
        await coordinator.loadModel('/models/qwen2.5-0.5b.gguf');

        final mockClient = MockClient((request) async {
          if (request.url.path.endsWith('/v1/chat/completions')) {
            return http.Response(
              jsonEncode({
                'id': 'chatcmpl-test-456',
                'object': 'chat.completion',
                'choices': [
                  {
                    'index': 0,
                    'message': {
                      'role': 'assistant',
                      'content': 'Sovereign AI operational.',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          buildTestApp(
            apiServer: apiServer,
            apiKeyService: apiKeyService,
            remoteAccessManager: remoteManager,
            modelState: modelState,
            settingsState: settingsState,
            chatState: chatState,
            storageService: storageService,
            child: SampleEndpointsScreen(httpClient: mockClient),
          ),
        );
        await tester.pumpAndSettle();

        final testButtons = find.text('Test');
        // Tap POST /v1/chat/completions Test button (second button)
        await tester.tap(testButtons.at(1));
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        // Verify completion output displayed
        expect(find.textContaining('HTTP 200 OK'), findsOneWidget);
        expect(find.textContaining('Assistant Output:'), findsOneWidget);
        expect(find.textContaining('Sovereign AI operational.'), findsWidgets);

        await tester.runAsync(() async {
          await apiServer.stop();
        });
      },
    );

    testWidgets('7. Sample Endpoints gracefully renders HTTP error responses', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await apiServer.start(port: 0);
      });

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Internal model queue failure',
              'type': 'server_error',
              'code': 500,
            },
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(
        buildTestApp(
          apiServer: apiServer,
          apiKeyService: apiKeyService,
          remoteAccessManager: remoteManager,
          modelState: modelState,
          settingsState: settingsState,
          chatState: chatState,
          storageService: storageService,
          child: SampleEndpointsScreen(httpClient: mockClient),
        ),
      );
      await tester.pumpAndSettle();

      final testButtons = find.text('Test');
      await tester.tap(testButtons.first);
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(
        find.textContaining('Internal model queue failure'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await apiServer.stop();
      });
    });

    testWidgets(
      '8. POST /v1/chat/completions Test button is disabled when no model is loaded',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.runAsync(() async {
          await apiServer.start(port: 0);
        });
        // No model loaded in coordinator (isLoaded == false)
        expect(coordinator.isLoaded, isFalse);

        await tester.pumpWidget(
          buildTestApp(
            apiServer: apiServer,
            apiKeyService: apiKeyService,
            remoteAccessManager: remoteManager,
            modelState: modelState,
            settingsState: settingsState,
            chatState: chatState,
            storageService: storageService,
            child: const SampleEndpointsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Only 1 enabled Test button should be present (for GET /v1/models)
        // The second button is disabled
        final filledButtons = tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .toList();
        expect(filledButtons.length, 2);
        expect(filledButtons[0].onPressed, isNotNull); // GET /v1/models enabled
        expect(
          filledButtons[1].onPressed,
          isNull,
        ); // POST /v1/chat/completions disabled

        await tester.runAsync(() async {
          await apiServer.stop();
        });
      },
    );
  });
}
