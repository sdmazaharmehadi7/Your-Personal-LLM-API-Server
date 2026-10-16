import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/chat_session.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/services/storage_service.dart';
import 'package:sovereign_ai/state/chat_state.dart';
import 'package:sovereign_ai/state/settings_state.dart';

void main() {
  late Directory tempDir;
  late LocalFileStorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sovereign_storage_test_');
    storageService = LocalFileStorageService(customBaseDirectory: tempDir);
    await storageService.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StorageService direct tests', () {
    test('initial load returns empty list when no file exists', () async {
      final result = await storageService.loadConversations();
      expect(result.sessions, isEmpty);
      expect(result.activeSessionId, isNull);
    });

    test(
      'saves and restores conversations with model IDs and messages',
      () async {
        final now = DateTime.utc(2026, 10, 10, 14, 0, 0);
        final session = ChatSession(
          id: 'sess_1',
          title: 'Offline Inference Discussion',
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 5)),
          modelId: 'smollm2-135m-q4',
          activeModelName: 'SmolLM2 135M Instruct',
          messages: [
            ChatMessage(
              id: 'msg_1',
              role: MessageRole.user,
              content: 'How does local GGUF work?',
              timestamp: now,
            ),
            ChatMessage(
              id: 'msg_2',
              role: MessageRole.assistant,
              content: 'It executes weights on your local hardware.',
              timestamp: now.add(const Duration(seconds: 2)),
            ),
          ],
        );

        await storageService.saveConversations([
          session,
        ], activeSessionId: 'sess_1');

        final restored = await storageService.loadConversations();
        expect(restored.sessions.length, 1);
        expect(restored.activeSessionId, 'sess_1');

        final s = restored.sessions.first;
        expect(s.id, 'sess_1');
        expect(s.title, 'Offline Inference Discussion');
        expect(s.modelId, 'smollm2-135m-q4');
        expect(s.activeModelName, 'SmolLM2 135M Instruct');
        expect(s.messages.length, 2);
        expect(s.messages[0].role, MessageRole.user);
        expect(s.messages[0].content, 'How does local GGUF work?');
        expect(s.messages[1].role, MessageRole.assistant);
        expect(
          s.messages[1].content,
          'It executes weights on your local hardware.',
        );
      },
    );

    test('updates conversation title and persists change', () async {
      final session = ChatSession(
        id: 'sess_update',
        title: 'Original Title',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
      );

      await storageService.saveConversations([
        session,
      ], activeSessionId: 'sess_update');

      final updatedSession = session.copyWith(title: 'Renamed Title');
      await storageService.saveConversations([
        updatedSession,
      ], activeSessionId: 'sess_update');

      final restored = await storageService.loadConversations();
      expect(restored.sessions.first.title, 'Renamed Title');
    });

    test('deletes conversations and clears chat storage', () async {
      final session1 = ChatSession(
        id: 's1',
        title: 'S1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
      );
      final session2 = ChatSession(
        id: 's2',
        title: 'S2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
      );

      await storageService.saveConversations([
        session1,
        session2,
      ], activeSessionId: 's1');

      // Delete s1
      await storageService.saveConversations([session2], activeSessionId: 's2');
      var restored = await storageService.loadConversations();
      expect(restored.sessions.length, 1);
      expect(restored.sessions.first.id, 's2');

      // Clear all
      await storageService.clearAllChatData();
      restored = await storageService.loadConversations();
      expect(restored.sessions, isEmpty);
      expect(restored.activeSessionId, isNull);
    });

    test('saves and restores theme and generation settings', () async {
      const customSettings = GenerationSettings(
        temperature: 0.45,
        topP: 0.85,
        contextWindow: 8192,
        maxTokens: 512,
        systemPrompt: 'Be concise.',
        useGpuAcceleration: false,
      );

      await storageService.saveSettings(
        themeMode: ThemeMode.light,
        settings: customSettings,
        lastLoadedModelPath: '/models/test.gguf',
      );

      final restored = await storageService.loadSettings();
      expect(restored, isNotNull);
      expect(restored!.themeMode, ThemeMode.light);
      expect(restored.settings.temperature, 0.45);
      expect(restored.settings.topP, 0.85);
      expect(restored.settings.contextWindow, 8192);
      expect(restored.settings.maxTokens, 512);
      expect(restored.settings.systemPrompt, 'Be concise.');
      expect(restored.settings.useGpuAcceleration, isFalse);
      expect(restored.lastLoadedModelPath, '/models/test.gguf');
    });

    test('handles empty file safely', () async {
      final file = File('${tempDir.path}/conversations.json');
      await file.writeAsString('   ');

      final restored = await storageService.loadConversations();
      expect(restored.sessions, isEmpty);
      expect(restored.activeSessionId, isNull);
    });

    test(
      'handles corrupted JSON by quarantining file without throwing',
      () async {
        final file = File('${tempDir.path}/conversations.json');
        await file.writeAsString('{corrupted json content: [unclosed');

        final restored = await storageService.loadConversations();
        expect(restored.sessions, isEmpty);
        expect(restored.activeSessionId, isNull);

        // Verify corrupted backup file was created
        final backupFiles = tempDir
            .listSync()
            .where(
              (f) => f.path.contains('.corrupted_') && f.path.endsWith('.bak'),
            )
            .toList();
        expect(backupFiles, isNotEmpty);
      },
    );

    test('handles incompatible root JSON format safely', () async {
      final file = File('${tempDir.path}/conversations.json');
      await file.writeAsString('["not", "a", "map"]');

      final restored = await storageService.loadConversations();
      expect(restored.sessions, isEmpty);
    });
  });

  group('App restart lifecycle simulation tests', () {
    test(
      'ChatState restores sessions and active session across restart',
      () async {
        // Phase 1: App session 1 creates and renames conversations
        final chatState1 = ChatState(storageService: storageService);
        await chatState1.init();

        chatState1.createNewChat(initialTitle: 'First Topic');
        final firstId = chatState1.activeSessionId!;

        chatState1.createNewChat(initialTitle: 'Second Topic');
        final secondId = chatState1.activeSessionId!;

        chatState1.renameSession(firstId, 'First Topic (Updated)');
        chatState1.selectSession(firstId);

        // Verify in-memory state before restart
        expect(chatState1.sessions.length, 2);
        expect(chatState1.activeSessionId, firstId);
        chatState1.dispose();

        // Phase 2: App restarts (new ChatState instance with same storage service)
        final chatState2 = ChatState(storageService: storageService);
        await chatState2.init();

        expect(chatState2.sessions.length, 2);
        expect(chatState2.activeSessionId, firstId);
        final restoredFirst = chatState2.sessions.firstWhere(
          (s) => s.id == firstId,
        );
        expect(restoredFirst.title, 'First Topic (Updated)');

        // Verify deletion persists across restart
        chatState2.deleteSession(secondId);
        chatState2.dispose();

        // Phase 3: App restarts again
        final chatState3 = ChatState(storageService: storageService);
        await chatState3.init();
        expect(chatState3.sessions.length, 1);
        expect(chatState3.sessions.first.id, firstId);
        chatState3.dispose();
      },
    );

    test(
      'SettingsState restores theme and preferences across restart',
      () async {
        final settings1 = SettingsState(storageService: storageService);
        await settings1.init();

        settings1.setThemeMode(ThemeMode.light);
        settings1.updateGenerationSettings(
          const GenerationSettings(temperature: 0.3, maxTokens: 256),
        );
        settings1.dispose();

        // Restart
        final settings2 = SettingsState(storageService: storageService);
        await settings2.init();

        expect(settings2.themeMode, ThemeMode.light);
        expect(settings2.generationSettings.temperature, 0.3);
        expect(settings2.generationSettings.maxTokens, 256);
        settings2.dispose();
      },
    );
  });

  group('InMemoryStorageService tests (Web compatibility)', () {
    test(
      'stores and loads conversations in memory without filesystem',
      () async {
        final webStorage = InMemoryStorageService();
        await webStorage.init();

        final session = ChatSession(
          id: 'web_sess_1',
          title: 'Web Session',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: [],
        );

        await webStorage.saveConversations([
          session,
        ], activeSessionId: 'web_sess_1');
        final loaded = await webStorage.loadConversations();
        expect(loaded.sessions.length, 1);
        expect(loaded.activeSessionId, 'web_sess_1');

        await webStorage.clearAllChatData();
        final cleared = await webStorage.loadConversations();
        expect(cleared.sessions, isEmpty);
        expect(cleared.activeSessionId, isNull);
      },
    );

    test('stores and loads settings in memory', () async {
      final webStorage = InMemoryStorageService();
      await webStorage.saveSettings(
        themeMode: ThemeMode.light,
        settings: const GenerationSettings(temperature: 0.2),
      );

      final loaded = await webStorage.loadSettings();
      expect(loaded, isNotNull);
      expect(loaded!.themeMode, ThemeMode.light);
      expect(loaded.settings.temperature, 0.2);
    });
  });
}
