import 'package:flutter/material.dart';

import '../models/generation_settings.dart';
import '../services/storage_service.dart';

class SettingsState extends ChangeNotifier {
  final IStorageService? storageService;
  ThemeMode _themeMode = ThemeMode.dark;
  GenerationSettings _generationSettings = const GenerationSettings();
  String? _lastLoadedModelPath;

  SettingsState({this.storageService});

  ThemeMode get themeMode => _themeMode;
  GenerationSettings get generationSettings => _generationSettings;
  String? get lastLoadedModelPath => _lastLoadedModelPath;

  Future<void> init() async {
    if (storageService == null) return;
    try {
      final stored = await storageService!.loadSettings();
      if (stored != null) {
        _themeMode = stored.themeMode;
        _generationSettings = stored.settings;
        _lastLoadedModelPath = stored.lastLoadedModelPath;
        notifyListeners();
      }
    } catch (_) {
      // Gracefully fall back to defaults
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _persistSettings();
    }
  }

  void updateGenerationSettings(GenerationSettings newSettings) {
    _generationSettings = newSettings;
    notifyListeners();
    _persistSettings();
  }

  void setLastLoadedModelPath(String? path) {
    if (_lastLoadedModelPath != path) {
      _lastLoadedModelPath = path;
      notifyListeners();
      _persistSettings();
    }
  }

  void resetToDefaults() {
    _generationSettings = const GenerationSettings();
    notifyListeners();
    _persistSettings();
  }

  void _persistSettings() {
    storageService?.saveSettings(
      themeMode: _themeMode,
      settings: _generationSettings,
      lastLoadedModelPath: _lastLoadedModelPath,
    );
  }
}
