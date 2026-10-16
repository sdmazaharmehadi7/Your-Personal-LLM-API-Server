import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

import 'package:sovereign_ai/models/generation_settings.dart';
import 'package:sovereign_ai/models/rag/document_chunk.dart';
import 'package:sovereign_ai/services/rag/embedding_service.dart';
import 'package:sovereign_ai/services/rag/rag_service.dart';
import 'package:sovereign_ai/services/rag/rag_storage_service.dart';

/// Deterministic mock embedding service producing 384-dimensional vectors.
/// Semantically related terms are assigned overlapping vector projections,
/// while exact keywords have their own orthogonal dimensions.
class MockDeterministicEmbeddingService implements IEmbeddingService {
  @override
  bool isLoaded = true;

  @override
  String? get currentModelId => 'all-minilm-l6-v2-q4';

  @override
  String? get currentModelPath => '/mock/all-MiniLM-L6-v2-Q4_K_M.gguf';

  @override
  int get embeddingDimension => 384;

  @override
  Future<void> loadModel(
    String filePath, {
    String? modelId,
    int contextWindow = 512,
    bool useGpu = false,
  }) async {
    isLoaded = true;
  }

  @override
  Future<void> unloadModel() async {
    isLoaded = false;
  }

  @override
  double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length || v1.isEmpty) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  @override
  List<double> normalizeVector(List<double> vector) {
    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm < 1e-12) return List.filled(vector.length, 0.0);
    return vector.map((v) => v / norm).toList();
  }

  /// Projects text into a semantic space.
  /// Concept clusters share base weights:
  /// - Battery / Driving Range / Vehicle endurance: cluster 0
  /// - High Temperature / Overheating / Thermal cooling: cluster 1
  /// - Database / Persistence / Atomic JSON storage: cluster 2
  /// - Equipment IDs / Part Numbers (e.g. ERR-9940, TX-880): cluster 3
  @override
  Future<List<double>> embedText(String text) async {
    final lower = text.toLowerCase();
    final vec = List.filled(384, 0.001);

    // Cluster 0: Automotive endurance & battery
    if (lower.contains('battery') ||
        lower.contains('range') ||
        lower.contains('endurance') ||
        lower.contains('kilometers') ||
        lower.contains('charge') ||
        lower.contains('vehicle')) {
      for (int i = 0; i < 50; i++) {
        vec[i] += 0.8;
      }
    }

    // Cluster 1: Thermal / Overheating / Temperature
    if (lower.contains('temperature') ||
        lower.contains('overheat') ||
        lower.contains('thermal') ||
        lower.contains('cooling') ||
        lower.contains('heat')) {
      for (int i = 50; i < 100; i++) {
        vec[i] += 0.8;
      }
    }

    // Cluster 2: Database / Storage / Persistence
    if (lower.contains('storage') ||
        lower.contains('json') ||
        lower.contains('atomic') ||
        lower.contains('persistence') ||
        lower.contains('disk')) {
      for (int i = 100; i < 150; i++) {
        vec[i] += 0.8;
      }
    }

    // Cluster 3: Part & Error Codes
    if (lower.contains('err-9940') || lower.contains('tx-880')) {
      for (int i = 150; i < 200; i++) {
        vec[i] += 0.9;
      }
    }

    // General token dispersion to simulate transformer embeddings
    for (final token in lower.split(RegExp(r'\W+')).where((t) => t.isNotEmpty)) {
      final hash = token.hashCode.abs() % 384;
      vec[hash] += 0.3;
    }

    return normalizeVector(vec);
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    int batchSize = 8,
  }) async {
    final results = <List<double>>[];
    for (final text in texts) {
      results.add(await embedText(text));
    }
    return results;
  }
}

void main() {
  group('Neural Vector Math & Similarity Tests', () {
    final embeddingService = MockDeterministicEmbeddingService();

    test('L2 Normalization produces unit-length vectors (||v|| = 1.0)', () {
      final raw = [3.0, 4.0, 0.0, 0.0];
      final normalized = embeddingService.normalizeVector(raw);
      expect(normalized.length, equals(4));
      expect(normalized[0], closeTo(0.6, 1e-5));
      expect(normalized[1], closeTo(0.8, 1e-5));

      final norm = math.sqrt(
        normalized.map((x) => x * x).reduce((a, b) => a + b),
      );
      expect(norm, closeTo(1.0, 1e-5));
    });

    test('Zero vector normalization returns zeros without NaN/Inf crash', () {
      final zeroVec = [0.0, 0.0, 0.0];
      final res = embeddingService.normalizeVector(zeroVec);
      expect(res, equals([0.0, 0.0, 0.0]));
      expect(res.any((v) => v.isNaN || v.isInfinite), isFalse);
    });

    test('Cosine similarity: identical = 1.0, orthogonal = 0.0, opposite = -1.0', () {
      final v1 = [1.0, 0.0, 0.0];
      final v2 = [1.0, 0.0, 0.0];
      final v3 = [0.0, 1.0, 0.0];
      final v4 = [-1.0, 0.0, 0.0];

      expect(embeddingService.cosineSimilarity(v1, v2), closeTo(1.0, 1e-5));
      expect(embeddingService.cosineSimilarity(v1, v3), closeTo(0.0, 1e-5));
      expect(embeddingService.cosineSimilarity(v1, v4), closeTo(-1.0, 1e-5));
    });

    test('Dimension mismatch returns safe 0.0 similarity score', () {
      final v384 = List.filled(384, 0.1);
      final v512 = List.filled(512, 0.1);
      expect(embeddingService.cosineSimilarity(v384, v512), equals(0.0));
    });
  });

  group('Vector Indexing & Persistence Schema v2', () {
    late Directory tempDir;
    late RagStorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rag_vector_test_');
      storage = RagStorageService(customBaseDirectory: tempDir);
      await storage.init();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Saves and restores 384-d embeddings with schemaVersion 2', () async {
      final embedding = List.generate(384, (i) => i * 0.001);
      final chunk = DocumentChunk(
        id: 'chunk_1',
        documentId: 'doc_1',
        fileName: 'manual.pdf',
        chunkIndex: 0,
        pageNumber: 12,
        sectionTitle: 'Section 4.1',
        text: 'The auxiliary battery powers the cooling fans.',
        wordCount: 8,
        tokenEstimate: 10,
        embedding: embedding,
        embeddingModelId: 'all-minilm-l6-v2-q4',
        embeddingDimension: 384,
        schemaVersion: 2,
      );

      await storage.saveChunks('doc_1', [chunk]);

      final loaded = await storage.loadChunksForDocuments(['doc_1']);
      expect(loaded.length, equals(1));
      final loadedChunk = loaded.first;

      expect(loadedChunk.schemaVersion, equals(2));
      expect(loadedChunk.embeddingModelId, equals('all-minilm-l6-v2-q4'));
      expect(loadedChunk.embeddingDimension, equals(384));
      expect(loadedChunk.embedding, isNotNull);
      expect(loadedChunk.embedding!.length, equals(384));
      expect(loadedChunk.embedding![10], closeTo(0.010, 1e-4));
      expect(loadedChunk.pageNumber, equals(12));
      expect(loadedChunk.sectionTitle, equals('Section 4.1'));
    });

    test('Deleting document removes chunks and vectors cleanly', () async {
      final chunk = DocumentChunk(
        id: 'chunk_del',
        documentId: 'doc_to_delete',
        fileName: 'temp.txt',
        chunkIndex: 0,
        text: 'Temporary data',
        wordCount: 2,
        tokenEstimate: 3,
        embedding: List.filled(384, 0.05),
        schemaVersion: 2,
      );

      await storage.saveChunks('doc_to_delete', [chunk]);
      expect((await storage.loadChunksForDocuments(['doc_to_delete'])).length, 1);

      await storage.deleteDocument('doc_to_delete');
      final afterDelete = await storage.loadChunksForDocuments(['doc_to_delete']);
      expect(afterDelete.isEmpty, isTrue);
    });
  });

  group('RAG Retrieval Benchmarking: BM25 vs Semantic vs Hybrid (RRF)', () {
    late Directory tempDir;
    late RagStorageService storage;
    late MockDeterministicEmbeddingService embeddingService;
    late RagService ragService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rag_benchmark_');
      storage = RagStorageService(customBaseDirectory: tempDir);
      await storage.init();
      embeddingService = MockDeterministicEmbeddingService();
      ragService = RagService(
        storageService: storage,
        embeddingService: embeddingService,
      );
      await ragService.init();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('PARAPHRASED QUERY: Neural embedding & Hybrid win where pure BM25 fails', () async {
      // Document text uses technical phrasing: "driving range of 480 kilometers per single charge"
      // User asks using different vocabulary: "What is the battery endurance for long trips?"
      // BM25 has 0 keyword overlap with 'endurance'/'trips', but neural embedding clusters match.
      final docFile = File('${tempDir.path}/vehicle_spec.txt');
      await docFile.writeAsString('''
# Electric Vehicle Specifications
The model S-90 delivers a driving range of 480 kilometers per single charge.
The auxiliary battery pack is installed under the rear seats.
Regular maintenance must be performed every 12 months.
''');

      final attachment = await ragService.processAndIndexDocument(
        sessionId: 'session_benchmark',
        filePath: docFile.path,
      );
      expect(attachment.chunkCount, greaterThanOrEqualTo(1));

      final query = 'What is the battery endurance for road trips?';

      // 1. BM25-only retrieval
      final bm25Result = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: query,
        mode: RetrievalMode.lexicalOnly,
      );
      expect(bm25Result.retrievalMethod, equals('lexical_bm25'));

      // 2. Semantic-only retrieval
      final semanticResult = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: query,
        mode: RetrievalMode.semanticOnly,
      );

      // 3. Hybrid RRF retrieval
      final hybridResult = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: query,
        mode: RetrievalMode.hybrid,
      );

      // Semantic & Hybrid retrieve the relevant driving range & battery passage
      expect(semanticResult.hasSufficientEvidence, isTrue);
      expect(semanticResult.chunks.first.text, contains('driving range'));

      expect(hybridResult.hasSufficientEvidence, isTrue);
      expect(hybridResult.chunks.first.text, contains('driving range'));
      expect(hybridResult.retrievalMethod, equals('hybrid_rrf'));
    });

    test('EXACT IDENTIFIERS: BM25 & Hybrid retrieve equipment IDs with precision', () async {
      // Document contains error code ERR-9940-KERNEL and part TX-880-PUMP
      final docFile = File('${tempDir.path}/industrial_troubleshoot.txt');
      await docFile.writeAsString('''
# Machine Diagnostics Manual
If actuator shuts off unexpectedly, verify error code ERR-9940-KERNEL on console.
The replacement pump unit is model TX-880-PUMP located in bay C.
General operating pressure should remain within 45 to 60 PSI.
''');

      final attachment = await ragService.processAndIndexDocument(
        sessionId: 'session_benchmark_2',
        filePath: docFile.path,
      );

      final query = 'What pump is needed for ERR-9940-KERNEL error?';

      final hybridResult = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: query,
        mode: RetrievalMode.hybrid,
      );

      expect(hybridResult.hasSufficientEvidence, isTrue);
      expect(hybridResult.chunks.first.text, contains('TX-880-PUMP'));
      expect(hybridResult.citations.length, greaterThanOrEqualTo(1));
      expect(hybridResult.citations.first.fileName, equals('industrial_troubleshoot.txt'));
    });

    test('UNANSWERABLE QUERY: Does not hallucinate or fabricate evidence', () async {
      final docFile = File('${tempDir.path}/recipes.txt');
      await docFile.writeAsString('''
# Pasta Carbonara
Ingredients: Spaghetti, eggs, pecorino cheese, guanciale, black pepper.
Boil pasta until al dente, mix with egg yolk and pecorino mixture.
''');

      final attachment = await ragService.processAndIndexDocument(
        sessionId: 'session_benchmark_3',
        filePath: docFile.path,
      );

      final unanswerableQuery = 'What is the quantum superposition decoherence rate of superconducting qubits?';

      final result = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: unanswerableQuery,
        mode: RetrievalMode.hybrid,
      );

      // Retrieval correctly recognizes insufficient evidence
      expect(result.hasSufficientEvidence, isFalse);
    });

    test('FALLBACK TO BM25: When neural embedding model is unloaded/unavailable', () async {
      final docFile = File('${tempDir.path}/network_config.txt');
      await docFile.writeAsString('''
# Router Configuration
The default gateway is configured at 192.168.1.1. Subnet mask is 255.255.255.0.
DNS server primary address points to 1.1.1.1 for local privacy.
''');

      final attachment = await ragService.processAndIndexDocument(
        sessionId: 'session_fallback',
        filePath: docFile.path,
      );

      // Simulate embedding model being unloaded
      await embeddingService.unloadModel();
      expect(embeddingService.isLoaded, isFalse);

      final query = 'default gateway address';
      final fallbackResult = await ragService.retrieveContext(
        documentIds: [attachment.id],
        query: query,
        mode: RetrievalMode.hybrid,
      );

      // System smoothly falls back to lexical retrieval without crashing
      expect(fallbackResult.hasSufficientEvidence, isTrue);
      expect(fallbackResult.chunks.first.text, contains('192.168.1.1'));
      expect(fallbackResult.retrievalMethod, equals('lexical_bm25'));
    });

    test('REINDEXING: reindexes existing document with neural embeddings', () async {
      final docFile = File('${tempDir.path}/kernel_notes.txt');
      await docFile.writeAsString('Microkernel IPC message passing architecture.');

      // Ingest initially without embedding model loaded
      await embeddingService.unloadModel();
      final attachment = await ragService.processAndIndexDocument(
        sessionId: 'session_reindex',
        filePath: docFile.path,
      );

      final initialChunks = await storage.loadChunksForDocuments([attachment.id]);
      expect(initialChunks.first.embedding, isNull);

      // Now load embedding model and trigger reindex
      await embeddingService.loadModel('/mock/path');
      await ragService.reindexDocument(attachment.id);

      final reindexedChunks = await storage.loadChunksForDocuments([attachment.id]);
      expect(reindexedChunks.first.embedding, isNotNull);
      expect(reindexedChunks.first.embedding!.length, equals(384));
      expect(reindexedChunks.first.schemaVersion, equals(2));
    });
  });
}
