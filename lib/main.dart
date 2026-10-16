import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'services/rag/embedding_service.dart';
import 'services/rag/rag_service.dart';
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
    final ragService = RagService(
      embeddingService: _embeddingService,
    );
    _chatState = ChatState(
      storageService: _storageService,
      ragService: ragService,
      modelState: _modelState,
    );

    _settingsState.init();
    _chatState.init();
    _modelState.init();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatState.dispose();
    _modelState.dispose();
    _settingsState.dispose();
    _embeddingService.unloadModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_settingsState, _modelState, _chatState]),
      builder: (context, _) {
        return AppScope(
          settingsState: _settingsState,
          modelState: _modelState,
          chatState: _chatState,
          storageService: _storageService,
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
