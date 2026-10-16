import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/generation_settings.dart';
import '../models/rag/document_attachment.dart';
import '../models/rag/rag_citation.dart';
import '../services/inference_service.dart';
import '../services/rag/embedding_service.dart';
import '../services/rag/rag_service.dart';
import '../services/rag/vector_retrieval_service.dart';
import '../services/storage_service.dart';
import 'model_state.dart';

class ChatState extends ChangeNotifier {
  static int _idCounter = 0;
  final IStorageService? storageService;
  final IRagService ragService;
  final ModelState? modelState;

  final List<ChatSession> _sessions = [];
  final Map<String, List<DocumentAttachment>> _sessionDocuments = {};

  String? _activeSessionId;
  bool _isGenerating = false;
  StreamSubscription<String>? _generationSubscription;
  Timer? _debounceTimer;
  Completer<void>? _generationCompleter;

  bool _isIndexingDocument = false;
  String? _indexingDocumentName;
  String? _indexingError;

  ChatState({
    this.storageService,
    IRagService? ragService,
    IEmbeddingService? embeddingService,
    this.modelState,
  }) : ragService = ragService ?? RagService(embeddingService: embeddingService);

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  bool get isGenerating => _isGenerating;
  String? get activeSessionId => _activeSessionId;

  bool get isIndexingDocument => _isIndexingDocument;
  String? get indexingDocumentName => _indexingDocumentName;
  String? get indexingError => _indexingError;

  ChatSession? get activeSession {
    if (_activeSessionId == null) return null;
    return _sessions.where((s) => s.id == _activeSessionId).firstOrNull;
  }

  List<DocumentAttachment> get activeSessionDocuments {
    if (_activeSessionId == null) return const [];
    return List.unmodifiable(_sessionDocuments[_activeSessionId] ?? const []);
  }

  Future<void> init() async {
    await ragService.init();

    if (storageService == null) return;
    try {
      final stored = await storageService!.loadConversations();
      _sessions.clear();
      _sessions.addAll(stored.sessions);

      if (stored.activeSessionId != null &&
          _sessions.any((s) => s.id == stored.activeSessionId)) {
        _activeSessionId = stored.activeSessionId;
      } else if (_sessions.isNotEmpty) {
        _activeSessionId = _sessions.first.id;
      } else {
        _activeSessionId = null;
      }

      // Load attached document metadata for loaded sessions
      for (final session in _sessions) {
        if (session.attachedDocumentIds.isNotEmpty) {
          try {
            final docs = await ragService.getDocumentsByIds(
              session.attachedDocumentIds,
            );
            _sessionDocuments[session.id] = docs;
          } catch (_) {}
        }
      }

      notifyListeners();
    } catch (_) {
      // Gracefully continue with in-memory sessions on error
    }
  }

  void createNewChat({
    String? initialTitle,
    String? modelId,
    String? activeModelName,
  }) {
    final now = DateTime.now();
    final newSession = ChatSession(
      id: 'session_${now.microsecondsSinceEpoch}_${++_idCounter}',
      title: initialTitle ?? 'New Conversation',
      createdAt: now,
      updatedAt: now,
      modelId: modelId,
      activeModelName: activeModelName,
      messages: [],
      attachedDocumentIds: const [],
    );
    _sessions.insert(0, newSession);
    _activeSessionId = newSession.id;
    _sessionDocuments[newSession.id] = [];
    notifyListeners();
    _persist();
  }

  void selectSession(String sessionId) {
    if (_activeSessionId != sessionId) {
      _activeSessionId = sessionId;

      // Lazy load documents if needed
      final session = activeSession;
      if (session != null &&
          session.attachedDocumentIds.isNotEmpty &&
          !_sessionDocuments.containsKey(sessionId)) {
        ragService.getDocumentsByIds(session.attachedDocumentIds).then((docs) {
          _sessionDocuments[sessionId] = docs;
          notifyListeners();
        });
      }

      notifyListeners();
      _persist();
    }
  }

  void renameSession(String sessionId, String newTitle) {
    final cleanTitle = newTitle.trim();
    if (cleanTitle.isEmpty) return;

    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      final updated = _sessions[index].copyWith(
        title: cleanTitle,
        updatedAt: DateTime.now(),
      );
      _sessions[index] = updated;
      notifyListeners();
      _persist();
    }
  }

  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    _sessionDocuments.remove(sessionId);

    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    notifyListeners();
    _persist();
  }

  void clearAllSessions() {
    _sessions.clear();
    _sessionDocuments.clear();
    _activeSessionId = null;
    notifyListeners();
    storageService?.clearAllChatData();
  }

  Future<void> _ensureEmbeddingModelLoaded([ModelState? externalModelState]) async {
    final ms = externalModelState ?? modelState;
    if (ms == null) return;
    final embedding = ragService.embeddingService;
    if (embedding == null || embedding.isLoaded) return;
    final installed = ms.installedEmbeddingModel;
    if (installed != null && installed.localPath != null) {
      try {
        await embedding.loadModel(
          installed.localPath!,
          modelId: installed.id,
        );
      } catch (_) {
        // Continue with lexical fallback
      }
    }
  }

  Future<DocumentAttachment?> attachDocument(
    String filePath, {
    ModelState? modelState,
  }) async {
    if (activeSession == null) {
      createNewChat(initialTitle: 'Document Chat');
    }

    final currentSession = activeSession!;
    final fileName = p.basename(filePath);

    _isIndexingDocument = true;
    _indexingDocumentName = fileName;
    _indexingError = null;
    notifyListeners();

    try {
      await _ensureEmbeddingModelLoaded(modelState);

      final doc = await ragService.processAndIndexDocument(
        sessionId: currentSession.id,
        filePath: filePath,
      );

      final updatedDocIds = List<String>.from(
        currentSession.attachedDocumentIds,
      );
      if (!updatedDocIds.contains(doc.id)) {
        updatedDocIds.add(doc.id);
      }

      final docs = List<DocumentAttachment>.from(
        _sessionDocuments[currentSession.id] ?? [],
      );
      final existingIdx = docs.indexWhere((d) => d.id == doc.id);
      if (existingIdx != -1) {
        docs[existingIdx] = doc;
      } else {
        docs.add(doc);
      }
      _sessionDocuments[currentSession.id] = docs;

      String newTitle = currentSession.title;
      if (currentSession.title == 'New Conversation' ||
          currentSession.title == 'Document Chat') {
        newTitle = 'Chat: $fileName';
      }

      _updateSession(
        currentSession.copyWith(
          title: newTitle,
          attachedDocumentIds: updatedDocIds,
          updatedAt: DateTime.now(),
        ),
      );
      _persist();
      return doc;
    } catch (e) {
      _indexingError = e.toString();
      rethrow;
    } finally {
      _isIndexingDocument = false;
      _indexingDocumentName = null;
      notifyListeners();
    }
  }

  Future<void> reindexDocument(
    String documentId, {
    ModelState? modelState,
  }) async {
    await _ensureEmbeddingModelLoaded(modelState);
    await ragService.reindexDocument(documentId);
    notifyListeners();
  }

  Future<void> removeDocument(String documentId) async {
    if (activeSession == null) return;
    final currentSession = activeSession!;

    final updatedDocIds = List<String>.from(currentSession.attachedDocumentIds)
      ..remove(documentId);

    final docs = List<DocumentAttachment>.from(
      _sessionDocuments[currentSession.id] ?? [],
    )..removeWhere((d) => d.id == documentId);
    _sessionDocuments[currentSession.id] = docs;

    _updateSession(
      currentSession.copyWith(
        attachedDocumentIds: updatedDocIds,
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
  }

  Future<void> sendMessage(
    String content, {
    required IInferenceService inferenceService,
    required GenerationSettings settings,
    ModelState? modelState,
  }) async {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty ||
        _isGenerating ||
        inferenceService.isGenerating) {
      return;
    }

    if (activeSession == null) {
      createNewChat(
        initialTitle: _deriveTitle(cleanContent),
        modelId: inferenceService.currentModelName,
        activeModelName: inferenceService.currentModelName,
      );
    }

    final currentSession = activeSession!;
    final now = DateTime.now();

    // 1. Append user message
    final userMessage = ChatMessage(
      id: 'msg_user_${now.microsecondsSinceEpoch}_${++_idCounter}',
      role: MessageRole.user,
      content: cleanContent,
      timestamp: now,
      status: MessageStatus.sent,
    );

    final updatedMessages = List<ChatMessage>.from(currentSession.messages)
      ..add(userMessage);

    String newTitle = currentSession.title;
    if (currentSession.messages.isEmpty &&
        (currentSession.title == 'New Conversation' ||
            currentSession.title == 'Document Chat')) {
      newTitle = _deriveTitle(cleanContent);
    }

    // 2. If model is NOT loaded, add an honest system notice without fake AI response
    if (!inferenceService.isLoaded) {
      final systemNotice = ChatMessage(
        id: 'msg_sys_${now.microsecondsSinceEpoch}_${++_idCounter}',
        role: MessageRole.system,
        content: 'Inference Engine Offline: No local GGUF model is loaded into memory. Load a model in the Model Manager to generate real offline responses.',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );
      updatedMessages.add(systemNotice);

      _updateSession(
        currentSession.copyWith(
          title: newTitle,
          updatedAt: DateTime.now(),
          messages: updatedMessages,
        ),
      );
      _persist();
      return;
    }

    // 3. Local RAG Context Retrieval (if documents are attached to this conversation)
    final attachedDocIds = currentSession.attachedDocumentIds;
    RetrievalResult? retrieval;
    List<RagCitation>? citations;
    String inferencePrompt = cleanContent;

    if (attachedDocIds.isNotEmpty) {
      try {
        await _ensureEmbeddingModelLoaded(modelState);

        retrieval = await ragService.retrieveContext(
          documentIds: attachedDocIds,
          query: cleanContent,
          mode: settings.retrievalMode,
          topK: settings.ragTopK,
        );

        if (retrieval.hasSufficientEvidence && retrieval.chunks.isNotEmpty) {
          inferencePrompt = ragService.buildGroundedUserPrompt(
            userQuery: cleanContent,
            retrieval: retrieval,
          );
          citations = retrieval.citations;
        } else {
          // Document attached, but question has no matching context
          inferencePrompt =
              'The user asked: "$cleanContent"\n\n'
              'Note: The user has attached documents to this chat, but the document index contains no matching context for this query. '
              'Please state clearly that the attached document(s) do not contain sufficient information to answer this question.';
        }
      } catch (_) {
        inferencePrompt = cleanContent;
      }
    }

    // 4. Model IS loaded: Start real streaming inference
    final assistantMessageId =
        'msg_ast_${now.microsecondsSinceEpoch}_${++_idCounter}';
    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.generating,
      citations: citations,
    );

    updatedMessages.add(assistantPlaceholder);
    _updateSession(
      currentSession.copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
        modelId: currentSession.modelId ?? inferenceService.currentModelName,
        activeModelName:
            currentSession.activeModelName ?? inferenceService.currentModelName,
        messages: updatedMessages,
      ),
    );
    _persist();

    _isGenerating = true;
    notifyListeners();

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    final buffer = StringBuffer();
    final completer = Completer<void>();
    _generationCompleter = completer;

    int tokenCount = 0;
    DateTime? firstTokenTime;
    double currentTokensPerSec = 0.0;

    try {
      // Build inference messages: Replace the last user message with grounded prompt if RAG is active
      final messagesForInference = List<ChatMessage>.from(
        updatedMessages.sublist(0, updatedMessages.length - 1),
      );
      if (messagesForInference.isNotEmpty &&
          messagesForInference.last.role == MessageRole.user &&
          inferencePrompt != cleanContent) {
        final lastUser = messagesForInference.last;
        messagesForInference[messagesForInference.length - 1] = lastUser
            .copyWith(content: inferencePrompt);
      }

      final tokenStream = inferenceService.generate(
        messages: messagesForInference,
        settings: settings,
      );

      _generationSubscription = tokenStream.listen(
        (token) {
          buffer.write(token);
          tokenCount++;
          final now = DateTime.now();
          firstTokenTime ??= now;
          final elapsedMs = now.difference(firstTokenTime!).inMilliseconds;
          if (elapsedMs >= 300) {
            currentTokensPerSec = (tokenCount / (elapsedMs / 1000.0));
          }

          _updateAssistantContent(
            assistantMessageId,
            buffer.toString(),
            status: MessageStatus.generating,
            tokensPerSecond: currentTokensPerSec > 0
                ? currentTokensPerSec
                : null,
            tokenCount: tokenCount,
            citations: citations,
          );
          _scheduleDebouncedPersistence();
        },
        onError: (Object error) async {
          _cancelDebouncedPersistence();
          final errorMsg = error is InferenceException
              ? error.message
              : 'Inference encountered an error during generation.';
          _updateAssistantContent(
            assistantMessageId,
            buffer.isNotEmpty
                ? '${buffer.toString()}\n\n[Inference interrupted: $errorMsg]'
                : '[Error: $errorMsg]',
            status: MessageStatus.error,
            errorMessage: errorMsg,
            tokensPerSecond: currentTokensPerSec > 0
                ? currentTokensPerSec
                : null,
            tokenCount: tokenCount > 0 ? tokenCount : null,
            citations: citations,
          );
          await _persist();
          if (!completer.isCompleted) completer.complete();
          _generationCompleter = null;
        },
        onDone: () async {
          _cancelDebouncedPersistence();
          _updateAssistantContent(
            assistantMessageId,
            buffer.toString().trim(),
            status: MessageStatus.sent,
            tokensPerSecond: currentTokensPerSec > 0
                ? currentTokensPerSec
                : null,
            tokenCount: tokenCount > 0 ? tokenCount : null,
            citations: citations,
          );
          await _persist();
          if (!completer.isCompleted) completer.complete();
          _generationCompleter = null;
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _cancelDebouncedPersistence();
      final errorMsg = e is InferenceException
          ? e.message
          : 'Failed to generate response on local hardware.';
      _updateAssistantContent(
        assistantMessageId,
        '[Error: $errorMsg]',
        status: MessageStatus.error,
        errorMessage: errorMsg,
        citations: citations,
      );
      await _persist();
      if (!completer.isCompleted) completer.complete();
      _generationCompleter = null;
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      _isGenerating = false;
      _generationSubscription = null;
      _generationCompleter = null;
      notifyListeners();
    }
  }

  Future<void> stopGeneration({
    required IInferenceService inferenceService,
  }) async {
    if (!_isGenerating) return;

    try {
      await WakelockPlus.disable();
    } catch (_) {}

    await inferenceService.stopGeneration();
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    if (!(_generationCompleter?.isCompleted ?? true)) {
      _generationCompleter?.complete();
    }
    _generationCompleter = null;
    _cancelDebouncedPersistence();
    _isGenerating = false;

    if (activeSession != null) {
      final messages = List<ChatMessage>.from(activeSession!.messages);
      final lastIdx = messages.indexWhere(
        (m) => m.status == MessageStatus.generating,
      );
      if (lastIdx != -1) {
        final lastMsg = messages[lastIdx];
        messages[lastIdx] = lastMsg.copyWith(
          content: lastMsg.content.trim().isNotEmpty
              ? '${lastMsg.content.trim()} [Stopped]'
              : '[Generation stopped by user]',
          status: MessageStatus.sent,
        );
        _updateSession(activeSession!.copyWith(messages: messages));
      }
    }

    notifyListeners();
    _persist();
  }

  void _updateAssistantContent(
    String messageId,
    String content, {
    required MessageStatus status,
    String? errorMessage,
    double? tokensPerSecond,
    int? tokenCount,
    List<RagCitation>? citations,
  }) {
    if (activeSession == null) return;
    final messages = List<ChatMessage>.from(activeSession!.messages);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      messages[idx] = messages[idx].copyWith(
        content: content,
        status: status,
        errorMessage: errorMessage,
        tokensPerSecond: tokensPerSecond,
        tokenCount: tokenCount,
        citations: citations ?? messages[idx].citations,
      );
      _updateSession(activeSession!.copyWith(messages: messages));
    }
  }

  void _updateSession(ChatSession session) {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      _sessions[idx] = session;
    }
    notifyListeners();
  }

  void _scheduleDebouncedPersistence() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 750), () {
      _persist();
    });
  }

  void _cancelDebouncedPersistence() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> _persist() {
    return storageService?.saveConversations(
          _sessions,
          activeSessionId: _activeSessionId,
        ) ??
        Future.value();
  }

  String _deriveTitle(String text) {
    final clean = text.replaceAll('\n', ' ').trim();
    if (clean.length <= 32) return clean;
    return '${clean.substring(0, 32)}...';
  }

  @override
  void dispose() {
    _cancelDebouncedPersistence();
    _generationSubscription?.cancel();
    if (!(_generationCompleter?.isCompleted ?? true)) {
      _generationCompleter?.complete();
    }
    _generationCompleter = null;
    super.dispose();
  }
}
