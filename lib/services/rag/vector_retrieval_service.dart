import 'dart:math' as math;

import '../../models/generation_settings.dart' show RetrievalMode;
import '../../models/rag/document_chunk.dart';
import '../../models/rag/rag_citation.dart';
import 'chunking_service.dart';

class RetrievalResult {
  final List<DocumentChunk> chunks;
  final List<RagCitation> citations;
  final bool hasSufficientEvidence;
  final String retrievalMethod; // 'hybrid_rrf', 'semantic_cosine', 'lexical_bm25'

  const RetrievalResult({
    required this.chunks,
    required this.citations,
    required this.hasSufficientEvidence,
    this.retrievalMethod = 'hybrid_rrf',
  });
}

class VectorRetrievalService {
  final double k1;
  final double b;
  final double bm25RelevanceThreshold;
  final double semanticRelevanceThreshold;
  final int rrfK; // Standard Cormack constant (60)
  final double semanticWeight;
  final double lexicalWeight;

  const VectorRetrievalService({
    this.k1 = 1.2,
    this.b = 0.75,
    this.bm25RelevanceThreshold = 0.05,
    this.semanticRelevanceThreshold = 0.20,
    this.rrfK = 60,
    this.semanticWeight = 0.60,
    this.lexicalWeight = 0.40,
  });

  RetrievalResult retrieveRelevantChunks({
    required String query,
    required List<DocumentChunk> allCandidateChunks,
    List<double>? queryEmbedding,
    RetrievalMode mode = RetrievalMode.hybrid,
    int topK = 4,
  }) {
    if (allCandidateChunks.isEmpty || query.trim().isEmpty) {
      return const RetrievalResult(
        chunks: [],
        citations: [],
        hasSufficientEvidence: false,
        retrievalMethod: 'none',
      );
    }

    final hasValidEmbedding = queryEmbedding != null && queryEmbedding.isNotEmpty;
    final hasChunkEmbeddings = allCandidateChunks.any(
      (c) => c.embedding != null && c.embedding!.isNotEmpty,
    );

    // If semantic requested but embeddings unavailable, gracefully fallback to lexical BM25
    final effectiveMode = (!hasValidEmbedding || !hasChunkEmbeddings)
        ? (mode == RetrievalMode.semanticOnly ? RetrievalMode.semanticOnly : RetrievalMode.lexicalOnly)
        : mode;

    switch (effectiveMode) {
      case RetrievalMode.semanticOnly:
        return _retrieveSemantic(
          query: query,
          queryEmbedding: queryEmbedding,
          allCandidateChunks: allCandidateChunks,
          topK: topK,
        );
      case RetrievalMode.lexicalOnly:
        return _retrieveLexical(
          query: query,
          allCandidateChunks: allCandidateChunks,
          topK: topK,
        );
      case RetrievalMode.hybrid:
        return _retrieveHybridRrf(
          query: query,
          queryEmbedding: queryEmbedding!,
          allCandidateChunks: allCandidateChunks,
          topK: topK,
        );
    }
  }

  RetrievalResult _retrieveSemantic({
    required String query,
    required List<double>? queryEmbedding,
    required List<DocumentChunk> allCandidateChunks,
    required int topK,
  }) {
    if (queryEmbedding == null || queryEmbedding.isEmpty) {
      return const RetrievalResult(
        chunks: [],
        citations: [],
        hasSufficientEvidence: false,
        retrievalMethod: 'semantic_cosine',
      );
    }

    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final scored = <({DocumentChunk chunk, double score})>[];

    for (final chunk in allCandidateChunks) {
      if (chunk.embedding == null || chunk.embedding!.isEmpty) continue;
      if (chunk.embedding!.length != queryEmbedding.length) continue;

      final similarity = cosineSimilarity(queryEmbedding, chunk.embedding!);
      if (similarity > 0.0) {
        scored.add((chunk: chunk, score: similarity));
      }
    }

    // Deterministic descending sort by score, breaking ties by chunk id
    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.id.compareTo(b.chunk.id);
    });

    final topResults = scored.take(topK).toList();
    if (topResults.isEmpty) {
      return const RetrievalResult(
        chunks: [],
        citations: [],
        hasSufficientEvidence: false,
        retrievalMethod: 'semantic_cosine',
      );
    }

    final maxScore = topResults.first.score;
    final chunks = <DocumentChunk>[];
    final citations = <RagCitation>[];

    for (final item in topResults) {
      chunks.add(item.chunk);
      citations.add(
        RagCitation(
          documentId: item.chunk.documentId,
          fileName: item.chunk.fileName,
          chunkIndex: item.chunk.chunkIndex,
          pageNumber: item.chunk.pageNumber,
          snippet: _createSnippet(item.chunk.text, queryWords),
          score: item.score,
        ),
      );
    }

    return RetrievalResult(
      chunks: chunks,
      citations: citations,
      hasSufficientEvidence: maxScore >= semanticRelevanceThreshold,
      retrievalMethod: 'semantic_cosine',
    );
  }

  RetrievalResult _retrieveLexical({
    required String query,
    required List<DocumentChunk> allCandidateChunks,
    required int topK,
  }) {
    final scored = _computeBm25Scores(query, allCandidateChunks);
    if (scored.isEmpty) {
      return const RetrievalResult(
        chunks: [],
        citations: [],
        hasSufficientEvidence: false,
        retrievalMethod: 'lexical_bm25',
      );
    }

    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final topResults = scored.take(topK).toList();
    final maxScore = topResults.first.score;

    final chunks = <DocumentChunk>[];
    final citations = <RagCitation>[];

    for (final item in topResults) {
      final normalizedScore = maxScore > 0 ? (item.score / maxScore) : 1.0;
      chunks.add(item.chunk);
      citations.add(
        RagCitation(
          documentId: item.chunk.documentId,
          fileName: item.chunk.fileName,
          chunkIndex: item.chunk.chunkIndex,
          pageNumber: item.chunk.pageNumber,
          snippet: _createSnippet(item.chunk.text, queryWords),
          score: normalizedScore,
        ),
      );
    }

    return RetrievalResult(
      chunks: chunks,
      citations: citations,
      hasSufficientEvidence: maxScore >= bm25RelevanceThreshold,
      retrievalMethod: 'lexical_bm25',
    );
  }

  RetrievalResult _retrieveHybridRrf({
    required String query,
    required List<double> queryEmbedding,
    required List<DocumentChunk> allCandidateChunks,
    required int topK,
  }) {
    // 1. Lexical BM25 Ranking
    final lexicalList = _computeBm25Scores(query, allCandidateChunks);
    final lexicalRankMap = <String, int>{};
    for (int i = 0; i < lexicalList.length; i++) {
      lexicalRankMap[lexicalList[i].chunk.id] = i + 1;
    }

    // 2. Semantic Cosine Ranking
    final semanticList = <({DocumentChunk chunk, double score})>[];
    for (final chunk in allCandidateChunks) {
      if (chunk.embedding != null &&
          chunk.embedding!.isNotEmpty &&
          chunk.embedding!.length == queryEmbedding.length) {
        final sim = cosineSimilarity(queryEmbedding, chunk.embedding!);
        if (sim > 0.0) {
          semanticList.add((chunk: chunk, score: sim));
        }
      }
    }
    semanticList.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.id.compareTo(b.chunk.id);
    });

    final semanticRankMap = <String, int>{};
    for (int i = 0; i < semanticList.length; i++) {
      semanticRankMap[semanticList[i].chunk.id] = i + 1;
    }

    // 3. Reciprocal Rank Fusion (RRF)
    final chunkMap = {for (var c in allCandidateChunks) c.id: c};
    final allRankedIds = <String>{...lexicalRankMap.keys, ...semanticRankMap.keys};

    if (allRankedIds.isEmpty) {
      return const RetrievalResult(
        chunks: [],
        citations: [],
        hasSufficientEvidence: false,
        retrievalMethod: 'hybrid_rrf',
      );
    }

    final fusedList = <({DocumentChunk chunk, double rrfScore, double rawSimilarity, double rawBm25})>[];

    for (final id in allRankedIds) {
      final chunk = chunkMap[id]!;
      final sRank = semanticRankMap[id];
      final lRank = lexicalRankMap[id];

      double rrfScore = 0.0;
      if (sRank != null) {
        rrfScore += semanticWeight / (rrfK + sRank);
      }
      if (lRank != null) {
        rrfScore += lexicalWeight / (rrfK + lRank);
      }

      final rawSim = sRank != null ? semanticList[sRank - 1].score : 0.0;
      final rawBm25 = lRank != null ? lexicalList[lRank - 1].score : 0.0;

      fusedList.add((
        chunk: chunk,
        rrfScore: rrfScore,
        rawSimilarity: rawSim,
        rawBm25: rawBm25,
      ));
    }

    fusedList.sort((a, b) {
      final cmp = b.rrfScore.compareTo(a.rrfScore);
      if (cmp != 0) return cmp;
      return a.chunk.id.compareTo(b.chunk.id);
    });

    final topResults = fusedList.take(topK).toList();
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final maxRrf = topResults.first.rrfScore;

    final chunks = <DocumentChunk>[];
    final citations = <RagCitation>[];

    for (final item in topResults) {
      final normalizedScore = maxRrf > 0 ? (item.rrfScore / maxRrf) : 1.0;
      chunks.add(item.chunk);
      citations.add(
        RagCitation(
          documentId: item.chunk.documentId,
          fileName: item.chunk.fileName,
          chunkIndex: item.chunk.chunkIndex,
          pageNumber: item.chunk.pageNumber,
          snippet: _createSnippet(item.chunk.text, queryWords),
          score: normalizedScore,
        ),
      );
    }

    // Evidence check: sufficient if top semantic similarity meets threshold OR top BM25 has positive match
    final topItem = topResults.first;
    final hasEvidence =
        topItem.rawSimilarity >= semanticRelevanceThreshold ||
        topItem.rawBm25 >= bm25RelevanceThreshold;

    return RetrievalResult(
      chunks: chunks,
      citations: citations,
      hasSufficientEvidence: hasEvidence,
      retrievalMethod: 'hybrid_rrf',
    );
  }

  List<({DocumentChunk chunk, double score})> _computeBm25Scores(
    String query,
    List<DocumentChunk> allCandidateChunks,
  ) {
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final queryTerms = ChunkingService.computeTermFrequencies(queryWords);
    if (queryTerms.isEmpty) return const [];

    final totalDocuments = allCandidateChunks.length;
    double totalDocLength = 0;
    final docFrequencies = <String, int>{};

    for (final chunk in allCandidateChunks) {
      totalDocLength += chunk.wordCount;
      for (final term in chunk.termFrequencies.keys) {
        docFrequencies[term] = (docFrequencies[term] ?? 0) + 1;
      }
    }

    final avgDocLength = totalDocuments > 0 ? (totalDocLength / totalDocuments) : 1.0;
    final scoredChunks = <({DocumentChunk chunk, double score})>[];

    for (final chunk in allCandidateChunks) {
      double score = 0.0;
      final docLength = chunk.wordCount > 0 ? chunk.wordCount : 1;

      for (final queryEntry in queryTerms.entries) {
        final term = queryEntry.key;
        final queryTermFreq = queryEntry.value;

        final chunkTermFreq = chunk.termFrequencies[term] ?? 0;
        if (chunkTermFreq == 0) continue;

        final docFreq = docFrequencies[term] ?? 0;
        final idf = math.log(1.0 + (totalDocuments - docFreq + 0.5) / (docFreq + 0.5));
        final safeIdf = math.max(0.01, idf);

        final numerator = chunkTermFreq * (k1 + 1.0);
        final denominator = chunkTermFreq + k1 * (1.0 - b + b * (docLength / avgDocLength));
        final tfScore = numerator / denominator;

        score += safeIdf * tfScore * (1 + math.log(queryTermFreq));
      }

      final lowerChunkText = chunk.text.toLowerCase();
      final lowerQuery = query.toLowerCase().trim();
      if (lowerChunkText.contains(lowerQuery)) {
        score += 2.0;
      }

      if (score > 0) {
        scoredChunks.add((chunk: chunk, score: score));
      }
    }

    scoredChunks.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.id.compareTo(b.chunk.id);
    });

    return scoredChunks;
  }

  static double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.isEmpty || v2.isEmpty || v1.length != v2.length) return 0.0;

    double dot = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < v1.length; i++) {
      final a = v1[i];
      final b = v2[i];
      dot += a * b;
      norm1 += a * a;
      norm2 += b * b;
    }

    if (norm1 <= 0.0 || norm2 <= 0.0) return 0.0;
    final denom = math.sqrt(norm1) * math.sqrt(norm2);
    if (denom <= 0.0) return 0.0;

    return (dot / denom).clamp(-1.0, 1.0);
  }

  String _createSnippet(String text, Iterable<String> queryWords) {
    final lowerText = text.toLowerCase();
    int bestIndex = -1;

    for (final rawWord in queryWords) {
      final term = ChunkingService.normalizeToken(rawWord);
      if (term.length < 3) continue;
      final idx = lowerText.indexOf(term);
      if (idx != -1) {
        if (bestIndex == -1 || idx < bestIndex) {
          bestIndex = idx;
        }
      }
    }

    if (bestIndex == -1) {
      return text.length > 140 ? '${text.substring(0, 137)}...' : text;
    }

    final start = math.max(0, bestIndex - 30);
    final end = math.min(text.length, bestIndex + 110);
    var snippet = text.substring(start, end).trim();

    if (start > 0) snippet = '...$snippet';
    if (end < text.length) snippet = '$snippet...';
    return snippet;
  }
}
