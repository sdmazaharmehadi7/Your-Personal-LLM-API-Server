import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chat_session.dart';
import '../models/generation_settings.dart';
import '../models/local_model.dart';

abstract class IStorageService {
  Future<void> init();

  Future<void> saveConversations(
    List<ChatSession> sessions, {
    String? activeSessionId,
  });

  Future<({List<ChatSession> sessions, String? activeSessionId})>
  loadConversations();

  Future<void> saveSettings({
    required ThemeMode themeMode,
    required GenerationSettings settings,
    String? lastLoadedModelPath,
  });

  Future<
    ({
      ThemeMode themeMode,
      GenerationSettings settings,
      String? lastLoadedModelPath,
    })?
  >
  loadSettings();

  Future<void> saveCustomModels(List<LocalModel> models);

  Future<List<LocalModel>> loadCustomModels();

  Future<void> clearAllChatData();

  Future<void> clearAll();

  String? get storageDirectoryPath;
}

class LocalFileStorageService implements IStorageService {
  static const int currentSchemaVersion = 1;
  static const String _conversationsFileName = 'conversations.json';
  static const String _settingsFileName = 'settings.json';
  static const String _modelsFileName = 'custom_models.json';

  final Directory? customBaseDirectory;
  Directory? _resolvedDirectory;
  bool _isInitialized = false;

  Future<void> _conversationsWriteQueue = Future.value();
  Future<void> _settingsWriteQueue = Future.value();
  Future<void> _modelsWriteQueue = Future.value();

  LocalFileStorageService({this.customBaseDirectory});

  @override
  String? get storageDirectoryPath => _resolvedDirectory?.path;

  @override
  Future<void> init() async {
    if (_isInitialized && _resolvedDirectory != null) return;

    if (customBaseDirectory != null) {
      _resolvedDirectory = customBaseDirectory;
    } else {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        _resolvedDirectory = Directory(p.join(appDocDir.path, 'sovereign_ai'));
      } catch (_) {
        // Fallback to system temp if documents directory is unavailable (e.g., in some test environments)
        _resolvedDirectory = Directory(
          p.join(Directory.systemTemp.path, 'sovereign_ai'),
        );
      }
    }

    if (!await _resolvedDirectory!.exists()) {
      await _resolvedDirectory!.create(recursive: true);
    }

    _isInitialized = true;
  }

  Future<Directory> _ensureDirectory() async {
    if (!_isInitialized || _resolvedDirectory == null) {
      await init();
    }
    return _resolvedDirectory!;
  }

  @override
  Future<void> saveConversations(
    List<ChatSession> sessions, {
    String? activeSessionId,
  }) {
    final payload = {
      'schemaVersion': currentSchemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'activeSessionId': activeSessionId,
      'conversations': sessions.map((s) => s.toJson()).toList(),
    };
    final jsonString = jsonEncode(payload);

    Future<void> writeOp() async {
      final dir = await _ensureDirectory();
      final file = File(p.join(dir.path, _conversationsFileName));
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final tmpFile = File(
        p.join(dir.path, '$_conversationsFileName.$nonce.tmp'),
      );

      try {
        // Atomic write pattern: write to unique temporary file first, then replace target
        await tmpFile.writeAsString(jsonString, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(file.path);
      } finally {
        if (await tmpFile.exists()) {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
      }
    }

    _conversationsWriteQueue = _conversationsWriteQueue.then(
      (_) => writeOp(),
      onError: (_) => writeOp(),
    );
    return _conversationsWriteQueue;
  }

  @override
  Future<({List<ChatSession> sessions, String? activeSessionId})>
  loadConversations() async {
    await _conversationsWriteQueue;
    final dir = await _ensureDirectory();
    final file = File(p.join(dir.path, _conversationsFileName));

    if (!await file.exists()) {
      return (sessions: <ChatSession>[], activeSessionId: null);
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return (sessions: <ChatSession>[], activeSessionId: null);
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        await _quarantineCorruptedFile(file, 'Invalid root object structure');
        return (sessions: <ChatSession>[], activeSessionId: null);
      }

      final migrated = _migrateConversations(decoded);
      final rawList = migrated['conversations'] as List<dynamic>? ?? [];
      final activeId = migrated['activeSessionId'] as String?;

      final sessions = rawList
          .whereType<Map<String, dynamic>>()
          .map((item) => ChatSession.fromJson(item))
          .toList();

      return (sessions: sessions, activeSessionId: activeId);
    } on FormatException {
      await _quarantineCorruptedFile(file, 'JSON parsing syntax error');
      return (sessions: <ChatSession>[], activeSessionId: null);
    } catch (_) {
      await _quarantineCorruptedFile(file, 'Unexpected schema error');
      return (sessions: <ChatSession>[], activeSessionId: null);
    }
  }

  @override
  Future<void> saveSettings({
    required ThemeMode themeMode,
    required GenerationSettings settings,
    String? lastLoadedModelPath,
  }) {
    final payload = {
      'schemaVersion': currentSchemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'themeMode': themeMode.name,
      'generationSettings': settings.toJson(),
      'lastLoadedModelPath': lastLoadedModelPath,
    };
    final jsonString = jsonEncode(payload);

    Future<void> writeOp() async {
      final dir = await _ensureDirectory();
      final file = File(p.join(dir.path, _settingsFileName));
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final tmpFile = File(p.join(dir.path, '$_settingsFileName.$nonce.tmp'));

      try {
        await tmpFile.writeAsString(jsonString, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(file.path);
      } finally {
        if (await tmpFile.exists()) {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
      }
    }

    _settingsWriteQueue = _settingsWriteQueue.then(
      (_) => writeOp(),
      onError: (_) => writeOp(),
    );
    return _settingsWriteQueue;
  }

  @override
  Future<
    ({
      ThemeMode themeMode,
      GenerationSettings settings,
      String? lastLoadedModelPath,
    })?
  >
  loadSettings() async {
    await _settingsWriteQueue;
    final dir = await _ensureDirectory();
    final file = File(p.join(dir.path, _settingsFileName));

    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        await _quarantineCorruptedFile(file, 'Invalid settings structure');
        return null;
      }

      final themeModeStr = decoded['themeMode'] as String?;
      final themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == themeModeStr,
        orElse: () => ThemeMode.dark,
      );

      final rawGenSettings =
          decoded['generationSettings'] as Map<String, dynamic>? ?? {};
      final settings = GenerationSettings.fromJson(rawGenSettings);
      final lastModel = decoded['lastLoadedModelPath'] as String?;

      return (
        themeMode: themeMode,
        settings: settings,
        lastLoadedModelPath: lastModel,
      );
    } on FormatException {
      await _quarantineCorruptedFile(file, 'Settings JSON format error');
      return null;
    } catch (_) {
      await _quarantineCorruptedFile(file, 'Settings unexpected error');
      return null;
    }
  }

  @override
  Future<void> clearAllChatData() async {
    Future<void> op() async {
      final dir = await _ensureDirectory();
      final file = File(p.join(dir.path, _conversationsFileName));
      if (await file.exists()) {
        await file.delete();
      }
      try {
        final list = dir.listSync();
        for (final item in list) {
          if (p.basename(item.path).startsWith(_conversationsFileName) &&
              item.path.endsWith('.tmp')) {
            try {
              item.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    _conversationsWriteQueue = _conversationsWriteQueue.then(
      (_) => op(),
      onError: (_) => op(),
    );
    return _conversationsWriteQueue;
  }

  @override
  Future<void> clearAll() async {
    Future<void> op() async {
      final dir = await _ensureDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    }

    final combined = Future.wait([
      _conversationsWriteQueue,
      _settingsWriteQueue,
      _modelsWriteQueue,
    ]);
    _conversationsWriteQueue = combined.then((_) => op(), onError: (_) => op());
    _settingsWriteQueue = _conversationsWriteQueue;
    _modelsWriteQueue = _conversationsWriteQueue;
    return _conversationsWriteQueue;
  }

  @override
  Future<void> saveCustomModels(List<LocalModel> models) {
    final payload = {
      'schemaVersion': currentSchemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'models': models.map((m) => m.toJson()).toList(),
    };
    final jsonString = jsonEncode(payload);

    Future<void> writeOp() async {
      final dir = await _ensureDirectory();
      final targetFile = File(p.join(dir.path, _modelsFileName));
      final tempFile = File(p.join(dir.path, '$_modelsFileName.tmp'));
      await tempFile.writeAsString(jsonString, flush: true);
      await tempFile.rename(targetFile.path);
    }

    _modelsWriteQueue = _modelsWriteQueue.then(
      (_) => writeOp(),
      onError: (_) => writeOp(),
    );
    return _modelsWriteQueue;
  }

  @override
  Future<List<LocalModel>> loadCustomModels() async {
    final dir = await _ensureDirectory();
    final file = File(p.join(dir.path, _modelsFileName));
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return [];
      final list = decoded['models'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => LocalModel.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _migrateConversations(Map<String, dynamic> raw) {
    var version = raw['schemaVersion'] as int? ?? 1;

    // Extensible migration pipeline for future schema evolution
    if (version < currentSchemaVersion) {
      // Execute version step migrations here when schema evolves
      raw['schemaVersion'] = currentSchemaVersion;
    }

    return raw;
  }

  Future<void> _quarantineCorruptedFile(File file, String reason) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final quarantinePath = '${file.path}.corrupted_$timestamp.bak';
      if (await file.exists()) {
        await file.rename(quarantinePath);
      }
    } catch (_) {
      // Silently ignore quarantine failure to avoid blocking caller
    }
  }
}

class InMemoryStorageService implements IStorageService {
  final List<ChatSession> _sessions = [];
  String? _activeSessionId;
  ThemeMode _themeMode = ThemeMode.dark;
  GenerationSettings _settings = const GenerationSettings();
  String? _lastLoadedModelPath;

  @override
  String? get storageDirectoryPath => 'Browser In-Memory Storage (Web)';

  @override
  Future<void> init() async {}

  @override
  Future<void> saveConversations(
    List<ChatSession> sessions, {
    String? activeSessionId,
  }) async {
    _sessions.clear();
    _sessions.addAll(sessions);
    _activeSessionId = activeSessionId;
  }

  @override
  Future<({List<ChatSession> sessions, String? activeSessionId})>
  loadConversations() async {
    return (
      sessions: List<ChatSession>.from(_sessions),
      activeSessionId: _activeSessionId,
    );
  }

  @override
  Future<void> saveSettings({
    required ThemeMode themeMode,
    required GenerationSettings settings,
    String? lastLoadedModelPath,
  }) async {
    _themeMode = themeMode;
    _settings = settings;
    _lastLoadedModelPath = lastLoadedModelPath;
  }

  @override
  Future<
    ({
      ThemeMode themeMode,
      GenerationSettings settings,
      String? lastLoadedModelPath,
    })?
  >
  loadSettings() async {
    return (
      themeMode: _themeMode,
      settings: _settings,
      lastLoadedModelPath: _lastLoadedModelPath,
    );
  }

  final List<LocalModel> _customModels = [];

  @override
  Future<void> saveCustomModels(List<LocalModel> models) async {
    _customModels.clear();
    _customModels.addAll(models);
  }

  @override
  Future<List<LocalModel>> loadCustomModels() async {
    return List<LocalModel>.from(_customModels);
  }

  @override
  Future<void> clearAllChatData() async {
    _sessions.clear();
    _activeSessionId = null;
  }

  @override
  Future<void> clearAll() async {
    _sessions.clear();
    _activeSessionId = null;
    _themeMode = ThemeMode.dark;
    _settings = const GenerationSettings();
    _lastLoadedModelPath = null;
    _customModels.clear();
  }
}
