class RagCitation {
  final String documentId;
  final String fileName;
  final int chunkIndex;
  final int? pageNumber;
  final String snippet;
  final double score;

  const RagCitation({
    required this.documentId,
    required this.fileName,
    required this.chunkIndex,
    this.pageNumber,
    required this.snippet,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
    'documentId': documentId,
    'fileName': fileName,
    'chunkIndex': chunkIndex,
    if (pageNumber != null) 'pageNumber': pageNumber,
    'snippet': snippet,
    'score': score,
  };

  factory RagCitation.fromJson(Map<String, dynamic> json) {
    return RagCitation(
      documentId: json['documentId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      chunkIndex: json['chunkIndex'] as int? ?? 0,
      pageNumber: json['pageNumber'] as int?,
      snippet: json['snippet'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
