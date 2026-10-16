import 'dart:math' as math;

import '../../models/rag/document_chunk.dart';
import 'document_parser_service.dart';

class ChunkingService {
  final int targetChunkWords;
  final int overlapWords;

  const ChunkingService({this.targetChunkWords = 250, this.overlapWords = 40});

  static final Set<String> _stopWords = {
    'a',
    'about',
    'above',
    'after',
    'again',
    'against',
    'all',
    'am',
    'an',
    'and',
    'any',
    'are',
    'aren\'t',
    'as',
    'at',
    'be',
    'because',
    'been',
    'before',
    'being',
    'below',
    'between',
    'both',
    'but',
    'by',
    'can\'t',
    'cannot',
    'could',
    'couldn\'t',
    'did',
    'didn\'t',
    'do',
    'does',
    'doesn\'t',
    'doing',
    'don\'t',
    'down',
    'during',
    'each',
    'few',
    'for',
    'from',
    'further',
    'had',
    'hadn\'t',
    'has',
    'hasn\'t',
    'have',
    'haven\'t',
    'having',
    'he',
    'he\'d',
    'he\'ll',
    'he\'s',
    'her',
    'here',
    'here\'s',
    'hers',
    'herself',
    'him',
    'himself',
    'his',
    'how',
    'how\'s',
    'i',
    'i\'d',
    'i\'ll',
    'i\'m',
    'i\'ve',
    'if',
    'in',
    'into',
    'is',
    'isn\'t',
    'it',
    'it\'s',
    'its',
    'itself',
    'let\'s',
    'me',
    'more',
    'most',
    'mustn\'t',
    'my',
    'myself',
    'no',
    'nor',
    'not',
    'of',
    'off',
    'on',
    'once',
    'only',
    'or',
    'other',
    'ought',
    'our',
    'ours',
    'ourselves',
    'out',
    'over',
    'own',
    'same',
    'shan\'t',
    'she',
    'she\'d',
    'she\'ll',
    'she\'s',
    'should',
    'shouldn\'t',
    'so',
    'some',
    'such',
    'than',
    'that',
    'that\'s',
    'the',
    'their',
    'theirs',
    'them',
    'themselves',
    'then',
    'there',
    'there\'s',
    'these',
    'they',
    'they\'d',
    'they\'ll',
    'they\'re',
    'they\'ve',
    'this',
    'those',
    'through',
    'to',
    'too',
    'under',
    'until',
    'up',
    'very',
    'was',
    'wasn\'t',
    'we',
    'we\'d',
    'we\'ll',
    'we\'re',
    'we\'ve',
    'were',
    'weren\'t',
    'what',
    'what\'s',
    'when',
    'when\'s',
    'where',
    'where\'s',
    'which',
    'while',
    'who',
    'who\'s',
    'whom',
    'why',
    'why\'s',
    'with',
    'won\'t',
    'would',
    'wouldn\'t',
    'you',
    'you\'d',
    'you\'ll',
    'you\'re',
    'you\'ve',
    'your',
    'yours',
    'yourself',
    'yourselves',
  };

  List<DocumentChunk> chunkDocument({
    required String documentId,
    required String fileName,
    required ParsedDocument parsedDocument,
  }) {
    final chunks = <DocumentChunk>[];
    int chunkIndex = 0;

    for (final page in parsedDocument.pages) {
      final pageText = page.text.trim();
      if (pageText.isEmpty) continue;

      // Extract paragraphs
      final paragraphs = pageText
          .split(RegExp(r'\n{2,}'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      List<String> currentWords = [];
      String? currentSection;

      for (final para in paragraphs) {
        // Detect potential headings / section titles (short lines ending without period)
        if (para.length < 80 &&
            !para.endsWith('.') &&
            para.split(' ').length < 10) {
          currentSection = para;
        }

        final paraWords = para
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        if (currentWords.length + paraWords.length <= targetChunkWords) {
          currentWords.addAll(paraWords);
        } else {
          // If we have accumulated words, emit a chunk
          if (currentWords.isNotEmpty) {
            final chunkText = currentWords.join(' ');
            chunks.add(
              _createChunk(
                documentId: documentId,
                fileName: fileName,
                chunkIndex: chunkIndex++,
                text: chunkText,
                pageNumber: page.pageNumber,
                sectionTitle: currentSection,
                words: currentWords,
              ),
            );

            // Keep overlap words from the end of currentWords
            final overlapCount = math.min(overlapWords, currentWords.length);
            final overlapStart = currentWords.length - overlapCount;
            currentWords = currentWords.sublist(overlapStart);
          }

          // If the single paragraph itself is larger than targetChunkWords, split it by sentences
          if (paraWords.length > targetChunkWords) {
            final sentences = _splitSentences(para);
            for (final sentence in sentences) {
              final sentenceWords = sentence
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .toList();
              if (currentWords.length + sentenceWords.length >
                      targetChunkWords &&
                  currentWords.isNotEmpty) {
                final chunkText = currentWords.join(' ');
                chunks.add(
                  _createChunk(
                    documentId: documentId,
                    fileName: fileName,
                    chunkIndex: chunkIndex++,
                    text: chunkText,
                    pageNumber: page.pageNumber,
                    sectionTitle: currentSection,
                    words: currentWords,
                  ),
                );
                final overlapCount = math.min(
                  overlapWords,
                  currentWords.length,
                );
                currentWords = currentWords.sublist(
                  currentWords.length - overlapCount,
                );
              }
              currentWords.addAll(sentenceWords);
            }
          } else {
            currentWords.addAll(paraWords);
          }
        }
      }

      // Flush remaining words on this page
      if (currentWords.isNotEmpty) {
        final chunkText = currentWords.join(' ');
        chunks.add(
          _createChunk(
            documentId: documentId,
            fileName: fileName,
            chunkIndex: chunkIndex++,
            text: chunkText,
            pageNumber: page.pageNumber,
            sectionTitle: currentSection,
            words: currentWords,
          ),
        );
        currentWords = [];
      }
    }

    return chunks;
  }

  DocumentChunk _createChunk({
    required String documentId,
    required String fileName,
    required int chunkIndex,
    required String text,
    required int pageNumber,
    required String? sectionTitle,
    required List<String> words,
  }) {
    final termFreqs = computeTermFrequencies(words);
    final wordCount = words.length;
    final tokenEstimate = (wordCount * 1.3).round();

    return DocumentChunk(
      id: 'chunk_${documentId}_$chunkIndex',
      documentId: documentId,
      fileName: fileName,
      chunkIndex: chunkIndex,
      text: text,
      pageNumber: pageNumber,
      sectionTitle: sectionTitle,
      wordCount: wordCount,
      tokenEstimate: tokenEstimate,
      termFrequencies: termFreqs,
    );
  }

  static Map<String, int> computeTermFrequencies(List<String> words) {
    final freqs = <String, int>{};
    for (final rawWord in words) {
      final token = normalizeToken(rawWord);
      if (token.length < 2 || _stopWords.contains(token)) continue;
      freqs[token] = (freqs[token] ?? 0) + 1;
    }
    return freqs;
  }

  static String normalizeToken(String word) {
    return word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  }

  List<String> _splitSentences(String text) {
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text
        .split(regex)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
