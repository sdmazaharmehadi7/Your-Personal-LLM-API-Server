import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:sovereign_ai/models/chat_message.dart';
import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/rag/document_attachment.dart';
import 'package:sovereign_ai/models/rag/document_chunk.dart';
import 'package:sovereign_ai/services/inference_service.dart';
import 'package:sovereign_ai/services/rag/chunking_service.dart';
import 'package:sovereign_ai/services/rag/document_parser_service.dart';
import 'package:sovereign_ai/services/rag/rag_service.dart';
import 'package:sovereign_ai/services/rag/rag_storage_service.dart';
import 'package:sovereign_ai/services/rag/vector_retrieval_service.dart';
import 'package:sovereign_ai/services/storage_service.dart';
import 'package:sovereign_ai/state/chat_state.dart';

class MockInferenceService implements IInferenceService {
  bool _isLoaded = true;
  bool _isGenerating = false;
  List<ChatMessage>? lastGeneratedMessages;

  @override
  bool get isLoaded => _isLoaded;
  @override
  bool get isGenerating => _isGenerating;
  @override
  String? get currentModelName => 'Test-Model-GGUF';
  @override
  String? get currentModelPath => '/mock/test-model.gguf';

  void setLoaded(bool loaded) => _isLoaded = loaded;

  @override
  Future<void> loadModel(
    String filePath, {
    int contextWindow = 2048,
    bool useGpu = true,
  }) async {
    _isLoaded = true;
  }

  @override
  Future<void> unloadModel() async {
    _isLoaded = false;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) async* {
    lastGeneratedMessages = List.from(messages);
    _isGenerating = true;
    yield 'Based on the attached document, ';
    yield 'the system architecture uses local GGUF models ';
    yield 'with offline vector retrieval.';
    _isGenerating = false;
  }

  @override
  Future<void> stopGeneration() async {
    _isGenerating = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tempDir;
  late DocumentParserService parser;
  late ChunkingService chunker;
  late VectorRetrievalService retrieval;
  late RagStorageService ragStorage;
  late RagService ragService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rag_comprehensive_test_');
    parser = const DocumentParserService(maxSizeBytes: 10 * 1024 * 1024);
    chunker = const ChunkingService(targetChunkWords: 50, overlapWords: 10);
    retrieval = const VectorRetrievalService();
    ragStorage = RagStorageService(customBaseDirectory: tempDir);
    await ragStorage.init();
    ragService = RagService(
      storageService: ragStorage,
      parserService: parser,
      chunkingService: chunker,
      retrievalService: retrieval,
    );
    await ragService.init();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Document Parsing Tests (Every Format)', () {
    test('Extracts plain text from TXT, Markdown, CSV, JSON, LOG', () async {
      final txtFile = File('${tempDir.path}/sample.txt')
        ..writeAsStringSync('Hello Sovereign AI plain text!');
      final mdFile = File('${tempDir.path}/sample.md')
        ..writeAsStringSync('# Heading\nMarkdown offline text.');
      final csvFile = File('${tempDir.path}/sample.csv')
        ..writeAsStringSync('id,name,role\n1,Alice,Engineer\n2,Bob,Architect');
      final jsonFile = File('${tempDir.path}/sample.json')
        ..writeAsStringSync('{"appName": "Sovereign AI", "offline": true}');
      final logFile = File('${tempDir.path}/sample.log')
        ..writeAsStringSync('[INFO] 2026-10-10 Server initialized locally.');

      final txtParsed = await parser.parseFile(txtFile.path);
      expect(txtParsed.fullText, contains('Hello Sovereign AI plain text!'));
      expect(txtParsed.pageCount, equals(1));

      final mdParsed = await parser.parseFile(mdFile.path);
      expect(mdParsed.fullText, contains('Markdown offline text.'));

      final csvParsed = await parser.parseFile(csvFile.path);
      expect(csvParsed.fullText, contains('Alice,Engineer'));

      final jsonParsed = await parser.parseFile(jsonFile.path);
      expect(jsonParsed.fullText, contains('"appName": "Sovereign AI"'));

      final logParsed = await parser.parseFile(logFile.path);
      expect(
        logParsed.fullText,
        contains('[INFO] 2026-10-10 Server initialized locally.'),
      );
    });

    test(
      'Extracts text from PDF preserving pages and detects scanned PDF',
      () async {
        // 1. Valid searchable PDF
        final pdfDoc = PdfDocument();
        final page1 = pdfDoc.pages.add();
        page1.graphics.drawString(
          'Sovereign AI PDF Page 1 Content',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
        final page2 = pdfDoc.pages.add();
        page2.graphics.drawString(
          'Sovereign AI PDF Page 2 Advanced RAG',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
        final pdfBytes = pdfDoc.saveSync();
        pdfDoc.dispose();

        final pdfFile = File('${tempDir.path}/document.pdf')
          ..writeAsBytesSync(pdfBytes);
        final parsed = await parser.parseFile(pdfFile.path);

        expect(parsed.pageCount, equals(2));
        expect(parsed.pages[0].text, contains('Page 1 Content'));
        expect(parsed.pages[1].text, contains('Page 2 Advanced RAG'));

        // 2. Empty/scanned PDF without selectable text triggers clear exception
        final emptyDoc = PdfDocument();
        emptyDoc.pages.add();
        emptyDoc.pages.add();
        final emptyBytes = emptyDoc.saveSync();
        emptyDoc.dispose();

        final emptyPdf = File('${tempDir.path}/scanned.pdf')
          ..writeAsBytesSync(emptyBytes);
        expect(
          () => parser.parseFile(emptyPdf.path),
          throwsA(
            isA<DocumentParsingException>().having(
              (e) => e.message,
              'message',
              contains('scanned image or photo PDF'),
            ),
          ),
        );
      },
    );

    test('Extracts structured text from DOCX format', () async {
      final archive = Archive();
      final xml =
          '<w:document><w:body><w:p><w:r><w:t>Sovereign Local DOCX Paragraph 1</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Paragraph 2 details</w:t></w:r></w:p></w:body></w:document>';
      archive.addFile(
        ArchiveFile('word/document.xml', xml.length, xml.codeUnits),
      );
      final zipData = ZipEncoder().encode(archive);

      final docxFile = File('${tempDir.path}/report.docx')
        ..writeAsBytesSync(zipData);
      final parsed = await parser.parseFile(docxFile.path);

      expect(parsed.fullText, contains('Sovereign Local DOCX Paragraph 1'));
      expect(parsed.fullText, contains('Paragraph 2 details'));
    });

    test('Rejects oversized and empty files with clear errors', () async {
      final emptyFile = File('${tempDir.path}/empty.txt')
        ..writeAsStringSync('');
      expect(
        () => parser.parseFile(emptyFile.path),
        throwsA(
          isA<DocumentParsingException>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );

      final smallLimitParser = const DocumentParserService(maxSizeBytes: 100);
      final largeFile = File('${tempDir.path}/large.txt')
        ..writeAsStringSync('A' * 200);
      expect(
        () => smallLimitParser.parseFile(largeFile.path),
        throwsA(
          isA<DocumentParsingException>().having(
            (e) => e.message,
            'message',
            contains('exceeds'),
          ),
        ),
      );
    });
  });

  group('Chunking and Retrieval Tests', () {
    test('Chunks text with boundary awareness and overlap', () {
      final parsed = ParsedDocument(
        fileName: 'guide.txt',
        fileExtension: 'txt',
        fileSizeBytes: 1000,
        sha256Hash: 'hash123',
        pages: [
          ParsedPage(
            pageNumber: 1,
            text:
                'Section One: Architecture\n\n'
                'Sovereign AI is built for local GGUF models without cloud dependencies. '
                'It keeps private user documents safe on device.\n\n'
                'Section Two: Performance\n\n'
                'The inference engine uses Metal on macOS and ARM64 optimizations on Android.',
          ),
        ],
        fullText: '...',
        isScanned: false,
        pageCount: 1,
      );

      final chunks = chunker.chunkDocument(
        documentId: 'doc1',
        fileName: 'guide.txt',
        parsedDocument: parsed,
      );

      expect(chunks, isNotEmpty);
      expect(chunks.first.documentId, equals('doc1'));
      expect(chunks.first.fileName, equals('guide.txt'));
      expect(chunks.first.pageNumber, equals(1));
      expect(chunks.first.termFrequencies, isNotEmpty);
    });

    test(
      'Vector retrieval scores relevant chunks higher than irrelevant ones',
      () {
        final chunk1 = DocumentChunk(
          id: 'c1',
          documentId: 'doc1',
          fileName: 'manual.pdf',
          chunkIndex: 0,
          pageNumber: 1,
          text: 'The battery life of the electric vehicle is estimated at 350 miles on a full charge.',
          wordCount: 16,
          tokenEstimate: 21,
          termFrequencies: ChunkingService.computeTermFrequencies([
            'battery',
            'life',
            'electric',
            'vehicle',
            'miles',
            'charge',
          ]),
        );

        final chunk2 = DocumentChunk(
          id: 'c2',
          documentId: 'doc1',
          fileName: 'manual.pdf',
          chunkIndex: 1,
          pageNumber: 2,
          text: 'The cooking instructions recommend baking the sourdough bread at 450 degrees Fahrenheit.',
          wordCount: 13,
          tokenEstimate: 17,
          termFrequencies: ChunkingService.computeTermFrequencies([
            'cooking',
            'instructions',
            'sourdough',
            'bread',
            'degrees',
            'fahrenheit',
          ]),
        );

        final result = retrieval.retrieveRelevantChunks(
          query: 'What is the electric battery range and mileage?',
          allCandidateChunks: [chunk1, chunk2],
          topK: 2,
        );

        expect(result.hasSufficientEvidence, isTrue);
        expect(result.chunks.first.id, equals('c1'));
        expect(result.citations.first.fileName, equals('manual.pdf'));
        expect(result.citations.first.pageNumber, equals(1));
      },
    );

    test('Irrelevant queries report insufficient evidence', () {
      final chunk = DocumentChunk(
        id: 'c1',
        documentId: 'doc1',
        fileName: 'notes.txt',
        chunkIndex: 0,
        text: 'Apples, oranges, and bananas are fruits rich in essential vitamins.',
        wordCount: 10,
        tokenEstimate: 13,
        termFrequencies: ChunkingService.computeTermFrequencies([
          'apples',
          'oranges',
          'bananas',
          'fruits',
          'vitamins',
        ]),
      );

      final result = retrieval.retrieveRelevantChunks(
        query: 'quantum mechanics wave function collapse',
        allCandidateChunks: [chunk],
        topK: 2,
      );

      expect(result.hasSufficientEvidence, isFalse);
      expect(result.chunks, isEmpty);
    });
  });

  group('RAG Coordinator and Storage Tests', () {
    test(
      'Deduplication prevents re-indexing same file and saves resources',
      () async {
        final sampleFile = File('${tempDir.path}/sovereign_spec.txt')
          ..writeAsStringSync(
            'Sovereign AI local offline document retrieval specifications.',
          );

        final doc1 = await ragService.processAndIndexDocument(
          sessionId: 'session_1',
          filePath: sampleFile.path,
        );

        expect(doc1.status, equals(DocumentStatus.indexed));
        expect(doc1.chunkCount, greaterThan(0));

        // Re-index identical file for session_2
        final doc2 = await ragService.processAndIndexDocument(
          sessionId: 'session_2',
          filePath: sampleFile.path,
        );

        expect(doc2.status, equals(DocumentStatus.indexed));
        expect(doc2.sha256Hash, equals(doc1.sha256Hash));
        expect(doc2.chunkCount, equals(doc1.chunkCount));
      },
    );

    test('Deletion cleans up document metadata and chunk files', () async {
      final file = File('${tempDir.path}/temporary.txt')
        ..writeAsStringSync('Temporary document for deletion test.');
      final doc = await ragService.processAndIndexDocument(
        sessionId: 'session_del',
        filePath: file.path,
      );

      var allDocs = await ragStorage.loadAllDocuments();
      expect(allDocs.any((d) => d.id == doc.id), isTrue);

      await ragService.deleteDocument(doc.id);

      allDocs = await ragStorage.loadAllDocuments();
      expect(allDocs.any((d) => d.id == doc.id), isFalse);

      final chunks = await ragStorage.loadChunksForDocuments([doc.id]);
      expect(chunks, isEmpty);
    });

    test('Conversation isolation ensures chunks only retrieved for attached documents', () async {
      final fileA = File('${tempDir.path}/confidential_project_a.txt')
        ..writeAsStringSync('Project Alpha secret key: 98765-XYZ.');
      final fileB = File('${tempDir.path}/confidential_project_b.txt')
        ..writeAsStringSync('Project Beta budget allocation: \$500,000 USD.');

      final docA = await ragService.processAndIndexDocument(
        sessionId: 'session_a',
        filePath: fileA.path,
      );
      final docB = await ragService.processAndIndexDocument(
        sessionId: 'session_b',
        filePath: fileB.path,
      );

      // Session A queries for secret key: only docA chunks are retrieved
      final resultA = await ragService.retrieveContext(
        documentIds: [docA.id],
        query: 'What is the secret key?',
      );
      expect(resultA.hasSufficientEvidence, isTrue);
      expect(resultA.chunks.every((c) => c.documentId == docA.id), isTrue);

      // Session B queries for secret key: docA is NOT in session B's attached documents!
      final resultB = await ragService.retrieveContext(
        documentIds: [docB.id],
        query: 'What is the secret key?',
      );
      expect(resultB.hasSufficientEvidence, isFalse);
    });
  });

  group('End-to-End ChatState RAG Integration Tests', () {
    test('Normal chat with NO attachments runs standard inference without RAG overhead', () async {
      final fileStorage = LocalFileStorageService(customBaseDirectory: tempDir);
      await fileStorage.init();

      final mockInference = MockInferenceService();
      final chatState = ChatState(
        storageService: fileStorage,
        ragService: ragService,
      );
      await chatState.init();

      chatState.createNewChat(initialTitle: 'Standard Chat');
      await chatState.sendMessage(
        'Hello Sovereign AI!',
        inferenceService: mockInference,
        settings: const GenerationSettings(),
      );

      final session = chatState.activeSession!;
      expect(session.attachedDocumentIds, isEmpty);
      expect(session.messages.length, equals(2));
      expect(session.messages.first.content, equals('Hello Sovereign AI!'));
      expect(session.messages.last.role, equals(MessageRole.assistant));
      expect(
        session.messages.last.citations,
        isNull,
      ); // Zero citations for normal chat
      expect(
        mockInference.lastGeneratedMessages!.last.content,
        equals('Hello Sovereign AI!'),
      );
      chatState.dispose();
    });

    test('Chat WITH attached document grounds prompt and stores citations', () async {
      final fileStorage = LocalFileStorageService(customBaseDirectory: tempDir);
      await fileStorage.init();

      final mockInference = MockInferenceService();
      final chatState = ChatState(
        storageService: fileStorage,
        ragService: ragService,
      );
      await chatState.init();

      final docFile = File('${tempDir.path}/sovereign_guide.txt')
        ..writeAsStringSync(
          'Sovereign AI Architecture Guide:\n'
          'The offline local RAG pipeline indexes user documents into semantic chunks '
          'and performs vector retrieval using pure on-device compute without external APIs.',
        );

      chatState.createNewChat();
      final attached = await chatState.attachDocument(docFile.path);
      expect(attached, isNotNull);
      expect(chatState.activeSessionDocuments.length, equals(1));

      await chatState.sendMessage(
        'How does Sovereign AI perform vector retrieval?',
        inferenceService: mockInference,
        settings: const GenerationSettings(),
      );

      final session = chatState.activeSession!;
      expect(session.messages.length, equals(2));

      // User message displayed cleanly in chat UI
      expect(
        session.messages.first.content,
        equals('How does Sovereign AI perform vector retrieval?'),
      );

      // The prompt sent to the LLM was grounded with verified document context
      final sentToLlm = mockInference.lastGeneratedMessages!.last.content;
      expect(
        sentToLlm,
        contains(
          'Here is verified background context from uploaded documents:',
        ),
      );
      expect(sentToLlm, contains('sovereign_guide.txt'));
      expect(sentToLlm, contains('pure on-device compute'));

      // Assistant message has citations
      final assistantMsg = session.messages.last;
      expect(assistantMsg.role, equals(MessageRole.assistant));
      expect(assistantMsg.citations, isNotNull);
      expect(
        assistantMsg.citations!.first.fileName,
        equals('sovereign_guide.txt'),
      );
      chatState.dispose();
    });

    test(
      'App restart restores attached documents and citations seamlessly',
      () async {
        final fileStorage = LocalFileStorageService(
          customBaseDirectory: tempDir,
        );
        await fileStorage.init();

        final mockInference = MockInferenceService();
        var chatState = ChatState(
          storageService: fileStorage,
          ragService: ragService,
        );
        await chatState.init();

        final docFile = File('${tempDir.path}/restart_test.txt')
          ..writeAsStringSync('Local persistence test data.');
        chatState.createNewChat(initialTitle: 'Restart Chat');
        final attached = await chatState.attachDocument(docFile.path);
        expect(attached, isNotNull);

        await chatState.sendMessage(
          'Check persistence',
          inferenceService: mockInference,
          settings: const GenerationSettings(),
        );

        final savedSessionId = chatState.activeSessionId!;
        chatState.dispose();

        // Simulate full app restart: create a new ChatState instance loading from disk
        final restartedChatState = ChatState(
          storageService: fileStorage,
          ragService: ragService,
        );
        await restartedChatState.init();

        expect(
          restartedChatState.sessions.any((s) => s.id == savedSessionId),
          isTrue,
        );
        final restoredSession = restartedChatState.sessions.firstWhere(
          (s) => s.id == savedSessionId,
        );
        expect(restoredSession.attachedDocumentIds, contains(attached!.id));

        final restoredDocs = restartedChatState.activeSessionDocuments;
        expect(restoredDocs.length, equals(1));
        expect(restoredDocs.first.fileName, equals('restart_test.txt'));

        final restoredAssistantMsg = restoredSession.messages.last;
        expect(restoredAssistantMsg.citations, isNotNull);
        restartedChatState.dispose();
      },
    );
  });
}
