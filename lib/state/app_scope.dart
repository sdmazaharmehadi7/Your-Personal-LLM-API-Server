import 'package:flutter/material.dart';

import '../services/api_server/api_key_service.dart';
import '../services/api_server/local_api_server.dart';
import '../services/inference_coordinator.dart';
import '../services/remote_access/remote_access_manager.dart';
import '../services/storage_service.dart';
import 'chat_state.dart';
import 'model_state.dart';
import 'settings_state.dart';

class AppScope extends InheritedWidget {
  final SettingsState settingsState;
  final ModelState modelState;
  final ChatState chatState;
  final IStorageService storageService;
  final LocalApiServer? apiServer;
  final ApiKeyService? apiKeyService;
  final RemoteAccessManager? remoteAccessManager;

  const AppScope({
    super.key,
    required this.settingsState,
    required this.modelState,
    required this.chatState,
    required this.storageService,
    this.apiServer,
    this.apiKeyService,
    this.remoteAccessManager,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final AppScope? result = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(result != null, 'No AppScope found in context');
    return result!;
  }

  static SettingsState settingsOf(BuildContext context) =>
      of(context).settingsState;

  static ModelState modelOf(BuildContext context) => of(context).modelState;

  static IInferenceCoordinator coordinatorOf(BuildContext context) =>
      of(context).modelState.coordinator;

  static LocalApiServer? apiServerOf(BuildContext context) =>
      of(context).apiServer;

  static ApiKeyService? apiKeyServiceOf(BuildContext context) =>
      of(context).apiKeyService;

  static RemoteAccessManager? remoteAccessOf(BuildContext context) =>
      of(context).remoteAccessManager;

  static ChatState chatOf(BuildContext context) => of(context).chatState;

  static IStorageService storageOf(BuildContext context) =>
      of(context).storageService;

  @override
  bool updateShouldNotify(AppScope oldWidget) => true;
}
