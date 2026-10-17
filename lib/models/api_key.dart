/// Permissions that can be granted to an API key.
enum ApiKeyPermission {
  chatCompletions(
    'chat_completions',
    'Generate chat completions (/v1/chat/completions)',
  ),
  modelsList('models_list', 'List loaded models (/v1/models)');

  final String id;
  final String description;

  const ApiKeyPermission(this.id, this.description);

  static ApiKeyPermission fromId(String id) {
    return ApiKeyPermission.values.firstWhere(
      (p) => p.id == id,
      orElse: () => ApiKeyPermission.chatCompletions,
    );
  }
}

/// Metadata and cryptographic hash for an API key.
///
/// Plaintext secrets are NEVER stored or represented in this class.
class ApiKeyMetadata {
  final String id;
  final String name;
  final String keyPrefix; // e.g. "sk-sov-1a2b..."
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isRevoked;
  final Set<ApiKeyPermission> permissions;
  final int rateLimitRpm; // Requests per minute
  final int maxConcurrentRequests;
  final List<String> allowedModels; // Empty means all loaded models allowed
  final int totalRequests;
  final DateTime? lastUsedAt;
  final String saltHex; // Cryptographic salt used for hashing
  final String hashHex; // HMAC-SHA256 hex digest

  const ApiKeyMetadata({
    required this.id,
    required this.name,
    required this.keyPrefix,
    required this.createdAt,
    this.expiresAt,
    this.isRevoked = false,
    required this.permissions,
    this.rateLimitRpm = 60,
    this.maxConcurrentRequests = 1,
    this.allowedModels = const [],
    this.totalRequests = 0,
    this.lastUsedAt,
    required this.saltHex,
    required this.hashHex,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isValid => !isRevoked && !isExpired;

  bool hasPermission(ApiKeyPermission permission) =>
      permissions.contains(permission);

  bool isModelAllowed(String? modelName) {
    if (allowedModels.isEmpty) return true;
    if (modelName == null || modelName.isEmpty) return false;
    final clean = modelName.trim().toLowerCase();
    return allowedModels.any(
      (m) =>
          m.trim().toLowerCase() == clean ||
          m.replaceAll('.gguf', '').toLowerCase() ==
              clean.replaceAll('.gguf', ''),
    );
  }

  ApiKeyMetadata copyWith({
    String? name,
    DateTime? expiresAt,
    bool? isRevoked,
    Set<ApiKeyPermission>? permissions,
    int? rateLimitRpm,
    int? maxConcurrentRequests,
    List<String>? allowedModels,
    int? totalRequests,
    DateTime? lastUsedAt,
  }) {
    return ApiKeyMetadata(
      id: id,
      name: name ?? this.name,
      keyPrefix: keyPrefix,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isRevoked: isRevoked ?? this.isRevoked,
      permissions: permissions ?? this.permissions,
      rateLimitRpm: rateLimitRpm ?? this.rateLimitRpm,
      maxConcurrentRequests:
          maxConcurrentRequests ?? this.maxConcurrentRequests,
      allowedModels: allowedModels ?? this.allowedModels,
      totalRequests: totalRequests ?? this.totalRequests,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      saltHex: saltHex,
      hashHex: hashHex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keyPrefix': keyPrefix,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'isRevoked': isRevoked,
      'permissions': permissions.map((p) => p.id).toList(),
      'rateLimitRpm': rateLimitRpm,
      'maxConcurrentRequests': maxConcurrentRequests,
      'allowedModels': allowedModels,
      'totalRequests': totalRequests,
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'saltHex': saltHex,
      'hashHex': hashHex,
    };
  }

  factory ApiKeyMetadata.fromJson(Map<String, dynamic> json) {
    return ApiKeyMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      keyPrefix: json['keyPrefix'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      isRevoked: json['isRevoked'] as bool? ?? false,
      permissions:
          (json['permissions'] as List<dynamic>?)
              ?.map((id) => ApiKeyPermission.fromId(id.toString()))
              .toSet() ??
          {ApiKeyPermission.chatCompletions, ApiKeyPermission.modelsList},
      rateLimitRpm: json['rateLimitRpm'] as int? ?? 60,
      maxConcurrentRequests: json['maxConcurrentRequests'] as int? ?? 1,
      allowedModels:
          (json['allowedModels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      totalRequests: json['totalRequests'] as int? ?? 0,
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      saltHex: json['saltHex'] as String,
      hashHex: json['hashHex'] as String,
    );
  }
}

/// The result returned only upon key creation.
///
/// Contains the ephemeral plaintext secret which must be displayed once to the user
/// and then immediately discarded from memory.
class GeneratedApiKeyResult {
  final ApiKeyMetadata metadata;
  final String plaintextSecret;

  const GeneratedApiKeyResult({
    required this.metadata,
    required this.plaintextSecret,
  });
}
