enum ModelDownloadStatus {
  notDownloaded,
  downloading,
  paused,
  downloaded,
  error,
}

enum ModelLoadStatus { unloaded, loading, loaded, error }

enum ModelSourceType { catalog, imported, customUrl }

class LocalModel {
  final String id;
  final String name;
  final String family;
  final String parameterSize;
  final String quantization;
  final double diskSizeGb;
  final double estimatedRamGb;
  final String description;
  final String filename;
  final String? downloadUrl;
  final String license;
  final double minRamGb;
  final String publisher;
  final ModelSourceType sourceType;
  final ModelDownloadStatus downloadStatus;
  final ModelLoadStatus loadStatus;
  final double downloadProgress; // 0.0 to 1.0
  final double downloadSpeedBytesPerSec;
  final int downloadedBytes;
  final int totalBytes;
  final String? localPath;
  final String? downloadError;
  final DateTime? lastUsedAt;
  final bool isEmbeddingModel;

  const LocalModel({
    required this.id,
    required this.name,
    required this.family,
    required this.parameterSize,
    required this.quantization,
    required this.diskSizeGb,
    required this.estimatedRamGb,
    required this.description,
    required this.filename,
    this.downloadUrl,
    this.license = 'Open Weights',
    this.minRamGb = 1.0,
    this.publisher = 'Community',
    this.sourceType = ModelSourceType.catalog,
    this.downloadStatus = ModelDownloadStatus.notDownloaded,
    this.loadStatus = ModelLoadStatus.unloaded,
    this.downloadProgress = 0.0,
    this.downloadSpeedBytesPerSec = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.localPath,
    this.downloadError,
    this.lastUsedAt,
    this.isEmbeddingModel = false,
  });

  bool get isDownloaded =>
      downloadStatus == ModelDownloadStatus.downloaded && localPath != null;

  LocalModel copyWith({
    String? id,
    String? name,
    String? family,
    String? parameterSize,
    String? quantization,
    double? diskSizeGb,
    double? estimatedRamGb,
    String? description,
    String? filename,
    String? downloadUrl,
    String? license,
    double? minRamGb,
    String? publisher,
    ModelSourceType? sourceType,
    ModelDownloadStatus? downloadStatus,
    ModelLoadStatus? loadStatus,
    double? downloadProgress,
    double? downloadSpeedBytesPerSec,
    int? downloadedBytes,
    int? totalBytes,
    String? localPath,
    String? downloadError,
    DateTime? lastUsedAt,
    bool? isEmbeddingModel,
    bool clearLocalPath = false,
    bool clearDownloadError = false,
  }) {
    return LocalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      family: family ?? this.family,
      parameterSize: parameterSize ?? this.parameterSize,
      quantization: quantization ?? this.quantization,
      diskSizeGb: diskSizeGb ?? this.diskSizeGb,
      estimatedRamGb: estimatedRamGb ?? this.estimatedRamGb,
      description: description ?? this.description,
      filename: filename ?? this.filename,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      license: license ?? this.license,
      minRamGb: minRamGb ?? this.minRamGb,
      publisher: publisher ?? this.publisher,
      sourceType: sourceType ?? this.sourceType,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      loadStatus: loadStatus ?? this.loadStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadSpeedBytesPerSec:
          downloadSpeedBytesPerSec ?? this.downloadSpeedBytesPerSec,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      downloadError: clearDownloadError
          ? null
          : (downloadError ?? this.downloadError),
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isEmbeddingModel: isEmbeddingModel ?? this.isEmbeddingModel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'family': family,
    'parameterSize': parameterSize,
    'quantization': quantization,
    'diskSizeGb': diskSizeGb,
    'estimatedRamGb': estimatedRamGb,
    'description': description,
    'filename': filename,
    'downloadUrl': downloadUrl,
    'license': license,
    'minRamGb': minRamGb,
    'publisher': publisher,
    'sourceType': sourceType.name,
    'localPath': localPath,
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
    if (isEmbeddingModel) 'isEmbeddingModel': true,
  };

  factory LocalModel.fromJson(Map<String, dynamic> json) {
    return LocalModel(
      id:
          json['id'] as String? ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Custom Model',
      family: json['family'] as String? ?? 'Custom',
      parameterSize: json['parameterSize'] as String? ?? 'Unknown',
      quantization: json['quantization'] as String? ?? 'GGUF',
      diskSizeGb: (json['diskSizeGb'] as num?)?.toDouble() ?? 0.0,
      estimatedRamGb: (json['estimatedRamGb'] as num?)?.toDouble() ?? 1.0,
      minRamGb: (json['minRamGb'] as num?)?.toDouble() ?? 1.0,
      description: json['description'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String?,
      license: json['license'] as String? ?? 'Open Weights',
      publisher: json['publisher'] as String? ?? 'Custom',
      sourceType: ModelSourceType.values.firstWhere(
        (s) => s.name == json['sourceType'],
        orElse: () => ModelSourceType.imported,
      ),
      localPath: json['localPath'] as String?,
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
      isEmbeddingModel: json['isEmbeddingModel'] as bool? ?? false,
    );
  }
}
