import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'services/api_server/api_key_service.dart';
import 'services/api_server/local_api_server.dart';
import 'services/rag/embedding_service.dart';
import 'services/rag/rag_service.dart';
import 'services/remote_access/remote_access_manager.dart';
import 'services/storage_service.dart';
import 'state/app_scope.dart';
import 'state/chat_state.dart';
import 'state/model_state.dart';
import 'state/settings_state.dart';
import 'ui/shell/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final IStorageService storageService = kIsWeb
      ? InMemoryStorageService()
      : LocalFileStorageService();
  await storageService.init();
  runApp(SovereignApp(storageService: storageService));
}

class SovereignApp extends StatefulWidget {
  final IStorageService? storageService;

  const SovereignApp({super.key, this.storageService});

  @override
  State<SovereignApp> createState() => _SovereignAppState();
}

class _SovereignAppState extends State<SovereignApp>
    with WidgetsBindingObserver {
  late final IStorageService _storageService;
  late final SettingsState _settingsState;
  late final ModelState _modelState;
  late final ChatState _chatState;
  late final IEmbeddingService _embeddingService;
  late final ApiKeyService _apiKeyService;
  late final LocalApiServer _apiServer;
  late final RemoteAccessManager _remoteAccessManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storageService =
        widget.storageService ??
        (kIsWeb ? InMemoryStorageService() : LocalFileStorageService());
    _settingsState = SettingsState(storageService: _storageService);
    _embeddingService = LocalEmbeddingService();
    _modelState = ModelState(
      storageService: _storageService,
      embeddingService: _embeddingService,
    );
    final ragService = RagService(embeddingService: _embeddingService);
    _chatState = ChatState(
      storageService: _storageService,
      ragService: ragService,
      modelState: _modelState,
    );
    _apiKeyService = ApiKeyService(
      storage: kIsWeb ? InMemoryApiKeyStorage() : FileApiKeyStorage(),
    );
    _apiServer = LocalApiServer(
      coordinator: _modelState.coordinator,
      apiKeyService: _apiKeyService,
      allowKeylessLocalhost: true,
    );
    _remoteAccessManager = RemoteAccessManager(apiServer: _apiServer);

    _settingsState.init();
    _chatState.init();
    _modelState.init();
    _apiKeyService.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Safe lifecycle handling: stop in-flight native generation when app goes to background
      if (_chatState.isGenerating ||
          _modelState.inferenceService.isGenerating) {
        _chatState.stopGeneration(
          inferenceService: _modelState.inferenceService,
        );
      }
    }

    if (state == AppLifecycleState.detached) {
      // Immediate cleanup of remote processes and open loopback listeners
      _remoteAccessManager.stopRemoteAccess();
      _apiServer.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remoteAccessManager.dispose();
    _apiServer.dispose();
    _apiKeyService.dispose();
    _chatState.dispose();
    _modelState.dispose();
    _settingsState.dispose();
    _embeddingService.unloadModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _settingsState,
        _modelState,
        _chatState,
        _apiServer,
        _apiKeyService,
        _remoteAccessManager,
      ]),
      builder: (context, _) {
        return AppScope(
          settingsState: _settingsState,
          modelState: _modelState,
          chatState: _chatState,
          storageService: _storageService,
          apiServer: _apiServer,
          apiKeyService: _apiKeyService,
          remoteAccessManager: _remoteAccessManager,
          child: MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _settingsState.themeMode,
            home: const AppShell(),
          ),
        );
      },
    );
  }
}
