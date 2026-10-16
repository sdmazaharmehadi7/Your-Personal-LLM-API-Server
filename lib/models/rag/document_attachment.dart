enum DocumentStatus { pending, parsing, chunking, indexed, error }

class DocumentAttachment {
  final String id;
  final String sessionId;
  final String fileName;
  final String filePath;
  final int fileSizeBytes;
  final String fileExtension;
  final String sha256Hash;
  final DateTime createdAt;
  final DocumentStatus status;
  final String? errorMessage;
  final int chunkCount;
  final int? pageCount;
  final bool isScanned;

  const DocumentAttachment({
    required this.id,
    required this.sessionId,
    required this.fileName,
    required this.filePath,
    required this.fileSizeBytes,
    required this.fileExtension,
    required this.sha256Hash,
    required this.createdAt,
    this.status = DocumentStatus.pending,
    this.errorMessage,
    this.chunkCount = 0,
    this.pageCount,
    this.isScanned = false,
  });

  DocumentAttachment copyWith({
    String? id,
    String? sessionId,
    String? fileName,
    String? filePath,
    int? fileSizeBytes,
    String? fileExtension,
    String? sha256Hash,
    DateTime? createdAt,
    DocumentStatus? status,
    String? errorMessage,
    int? chunkCount,
    int? pageCount,
    bool? isScanned,
  }) {
    return DocumentAttachment(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      fileExtension: fileExtension ?? this.fileExtension,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      chunkCount: chunkCount ?? this.chunkCount,
      pageCount: pageCount ?? this.pageCount,
      isScanned: isScanned ?? this.isScanned,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'fileName': fileName,
    'filePath': filePath,
    'fileSizeBytes': fileSizeBytes,
    'fileExtension': fileExtension,
    'sha256Hash': sha256Hash,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'chunkCount': chunkCount,
    if (pageCount != null) 'pageCount': pageCount,
    'isScanned': isScanned,
  };

  factory DocumentAttachment.fromJson(Map<String, dynamic> json) {
    return DocumentAttachment(
      id:
          json['id'] as String? ??
          'doc_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: json['sessionId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'Unnamed Document',
      filePath: json['filePath'] as String? ?? '',
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      fileExtension: json['fileExtension'] as String? ?? '',
      sha256Hash: json['sha256Hash'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: DocumentStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DocumentStatus.pending,
      ),
      errorMessage: json['errorMessage'] as String?,
      chunkCount: json['chunkCount'] as int? ?? 0,
      pageCount: json['pageCount'] as int?,
      isScanned: json['isScanned'] as bool? ?? false,
    );
  }
}
