import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import 'chat_state.dart';
import 'model_state.dart';
import 'settings_state.dart';

class AppScope extends InheritedWidget {
  final SettingsState settingsState;
  final ModelState modelState;
  final ChatState chatState;
  final IStorageService storageService;

  const AppScope({
    super.key,
    required this.settingsState,
    required this.modelState,
    required this.chatState,
    required this.storageService,
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

  static ChatState chatOf(BuildContext context) => of(context).chatState;

  static IStorageService storageOf(BuildContext context) =>
      of(context).storageService;

  @override
  bool updateShouldNotify(AppScope oldWidget) => true;
}
