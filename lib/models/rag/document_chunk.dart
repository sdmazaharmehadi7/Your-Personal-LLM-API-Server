class DocumentChunk {
  final String id;
  final String documentId;
  final String fileName;
  final int chunkIndex;
  final String text;
  final int? pageNumber;
  final String? sectionTitle;
  final int wordCount;
  final int tokenEstimate;
  final Map<String, int> termFrequencies;
  final List<double>? embedding;
  final String? embeddingModelId;
  final int? embeddingDimension;
  final int schemaVersion;

  const DocumentChunk({
    required this.id,
    required this.documentId,
    required this.fileName,
    required this.chunkIndex,
    required this.text,
    this.pageNumber,
    this.sectionTitle,
    required this.wordCount,
    required this.tokenEstimate,
    this.termFrequencies = const {},
    this.embedding,
    this.embeddingModelId,
    this.embeddingDimension,
    this.schemaVersion = 2,
  });

  DocumentChunk copyWith({
    String? id,
    String? documentId,
    String? fileName,
    int? chunkIndex,
    String? text,
    int? pageNumber,
    String? sectionTitle,
    int? wordCount,
    int? tokenEstimate,
    Map<String, int>? termFrequencies,
    List<double>? embedding,
    String? embeddingModelId,
    int? embeddingDimension,
    int? schemaVersion,
  }) {
    return DocumentChunk(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      fileName: fileName ?? this.fileName,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      text: text ?? this.text,
      pageNumber: pageNumber ?? this.pageNumber,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      wordCount: wordCount ?? this.wordCount,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
      termFrequencies: termFrequencies ?? this.termFrequencies,
      embedding: embedding ?? this.embedding,
      embeddingModelId: embeddingModelId ?? this.embeddingModelId,
      embeddingDimension: embeddingDimension ?? this.embeddingDimension,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'fileName': fileName,
    'chunkIndex': chunkIndex,
    'text': text,
    if (pageNumber != null) 'pageNumber': pageNumber,
    if (sectionTitle != null) 'sectionTitle': sectionTitle,
    'wordCount': wordCount,
    'tokenEstimate': tokenEstimate,
    'termFrequencies': termFrequencies,
    if (embedding != null) 'embedding': embedding,
    if (embeddingModelId != null) 'embeddingModelId': embeddingModelId,
    if (embeddingDimension != null) 'embeddingDimension': embeddingDimension,
    'schemaVersion': schemaVersion,
  };

  factory DocumentChunk.fromJson(Map<String, dynamic> json) {
    final rawTerms = json['termFrequencies'] as Map<String, dynamic>? ?? {};
    final terms = <String, int>{};
    for (final entry in rawTerms.entries) {
      if (entry.value is int) {
        terms[entry.key] = entry.value as int;
      }
    }

    final rawEmbedding = json['embedding'] as List<dynamic>?;
    final embedding = rawEmbedding?.map((e) => (e as num).toDouble()).toList();

    return DocumentChunk(
      id:
          json['id'] as String? ??
          'chunk_${DateTime.now().millisecondsSinceEpoch}',
      documentId: json['documentId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      chunkIndex: json['chunkIndex'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      pageNumber: json['pageNumber'] as int?,
      sectionTitle: json['sectionTitle'] as String?,
      wordCount: json['wordCount'] as int? ?? 0,
      tokenEstimate: json['tokenEstimate'] as int? ?? 0,
      termFrequencies: terms,
      embedding: embedding,
      embeddingModelId: json['embeddingModelId'] as String?,
      embeddingDimension: json['embeddingDimension'] as int?,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
    );
  }
}
