import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/api_key.dart';

/// Result of an authentication and authorization check.
class AuthResult {
  final bool isSuccess;
  final ApiKeyMetadata? key;
  final int statusCode;
  final String? errorMessage;
  final String? errorCode;
  final int? retryAfterSeconds;

  const AuthResult._({
    required this.isSuccess,
    this.key,
    required this.statusCode,
    this.errorMessage,
    this.errorCode,
    this.retryAfterSeconds,
  });

  factory AuthResult.success(ApiKeyMetadata key) {
    return AuthResult._(isSuccess: true, key: key, statusCode: HttpStatus.ok);
  }

  factory AuthResult.unauthorized(
    String message, {
    String code = 'invalid_api_key',
  }) {
    return AuthResult._(
      isSuccess: false,
      statusCode: HttpStatus.unauthorized,
      errorMessage: message,
      errorCode: code,
    );
  }

  factory AuthResult.forbidden(
    String message, {
    String code = 'permission_denied',
  }) {
    return AuthResult._(
      isSuccess: false,
      statusCode: HttpStatus.forbidden,
      errorMessage: message,
      errorCode: code,
    );
  }

  factory AuthResult.rateLimited(int retryAfter, String message) {
    return AuthResult._(
      isSuccess: false,
      statusCode: HttpStatus.tooManyRequests,
      errorMessage: message,
      errorCode: 'rate_limit_exceeded',
      retryAfterSeconds: retryAfter,
    );
  }

  factory AuthResult.concurrencyLimited(String message) {
    return AuthResult._(
      isSuccess: false,
      statusCode: HttpStatus.tooManyRequests,
      errorMessage: message,
      errorCode: 'concurrency_limit_exceeded',
      retryAfterSeconds: 1,
    );
  }
}

/// Abstract storage interface for API key metadata and cryptographic hashes.
/// Plaintext secrets are NEVER stored.
abstract class IApiKeyStorage {
  Future<void> init();
  Future<List<ApiKeyMetadata>> loadKeys();
  Future<void> saveKeys(List<ApiKeyMetadata> keys);
}

/// In-memory storage for unit tests.
class InMemoryApiKeyStorage implements IApiKeyStorage {
  List<ApiKeyMetadata> _keys = [];

  InMemoryApiKeyStorage([List<ApiKeyMetadata>? initialKeys]) {
    if (initialKeys != null) {
      _keys = List.from(initialKeys);
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<List<ApiKeyMetadata>> loadKeys() async {
    return List.unmodifiable(_keys);
  }

  @override
  Future<void> saveKeys(List<ApiKeyMetadata> keys) async {
    _keys = List.from(keys);
  }
}

/// Secure filesystem storage inside the macOS sandboxed Application Support directory.
class FileApiKeyStorage implements IApiKeyStorage {
  final Directory? customBaseDirectory;
  Directory? _resolvedDirectory;
  static const String _fileName = 'api_keys.json';

  FileApiKeyStorage({this.customBaseDirectory});

  @override
  Future<void> init() async {
    if (_resolvedDirectory != null) return;

    if (customBaseDirectory != null) {
      _resolvedDirectory = customBaseDirectory;
    } else {
      try {
        final dir = await getApplicationSupportDirectory();
        _resolvedDirectory = Directory(p.join(dir.path, 'sovereign_ai'));
      } catch (_) {
        // Fallback for tests or environments without path_provider
        _resolvedDirectory = Directory(
          p.join(Directory.systemTemp.path, 'sovereign_ai'),
        );
      }
    }

    if (!await _resolvedDirectory!.exists()) {
      await _resolvedDirectory!.create(recursive: true);
    }
  }

  File _getFile() => File(p.join(_resolvedDirectory!.path, _fileName));

  @override
  Future<List<ApiKeyMetadata>> loadKeys() async {
    await init();
    final file = _getFile();
    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => ApiKeyMetadata.fromJson(item))
          .toList();
    } catch (e) {
      // In case of corruption, do not crash; return empty and preserve original file
      return [];
    }
  }

  @override
  Future<void> saveKeys(List<ApiKeyMetadata> keys) async {
    await init();
    final file = _getFile();
    final tempFile = File('${file.path}.tmp');

    final jsonList = keys.map((k) => k.toJson()).toList();
    final content = const JsonEncoder.withIndent('  ').convert(jsonList);

    // Atomic write pattern: write to temp file then rename
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);

    // Enforce restrictive permissions on POSIX systems (0600: read/write by owner only)
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }
}

/// Core API Key management and authentication service.
class ApiKeyService extends ChangeNotifier {
  final IApiKeyStorage _storage;
  final List<ApiKeyMetadata> _keys = [];
  bool _isInitialized = false;

  // Rate limiting & concurrency tracking per key ID
  final Map<String, List<DateTime>> _requestTimestamps = {};
  final Map<String, int> _activeRequestCounts = {};

  ApiKeyService({IApiKeyStorage? storage})
    : _storage = storage ?? FileApiKeyStorage();

  bool get isInitialized => _isInitialized;
  List<ApiKeyMetadata> get keys => List.unmodifiable(_keys);
  int get totalKeysCount => _keys.length;
  int get activeKeysCount => _keys.where((k) => k.isValid).length;

  Future<void> init() async {
    if (_isInitialized) return;
    await _storage.init();
    final loaded = await _storage.loadKeys();
    _keys.clear();
    _keys.addAll(loaded);
    _isInitialized = true;
    notifyListeners();
  }

  /// Generates a cryptographically secure API key with at least 256 bits of entropy.
  ///
  /// The plaintext secret is returned ONLY in the [GeneratedApiKeyResult] and is never persisted.
  Future<GeneratedApiKeyResult> createKey({
    required String name,
    DateTime? expiresAt,
    Set<ApiKeyPermission>? permissions,
    int rateLimitRpm = 60,
    int maxConcurrentRequests = 1,
    List<String> allowedModels = const [],
  }) async {
    await _ensureInitialized();

    // 1. Generate 32 bytes (256 bits) of cryptographically secure random bytes
    final secureRandom = Random.secure();
    final secretBytes = List<int>.generate(
      32,
      (_) => secureRandom.nextInt(256),
    );
    final secretHex = secretBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final plaintextSecret = 'sk-sov-$secretHex';

    // 2. Generate a 16-byte random salt
    final saltBytes = List<int>.generate(16, (_) => secureRandom.nextInt(256));
    final saltHex = saltBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // 3. Compute HMAC-SHA256 hash using the salt as the key
    final hashHex = _computeHmac(plaintextSecret, saltHex);

    // 4. Generate truncated prefix for identification (e.g. sk-sov-1a2b...9z0a)
    final keyPrefix =
        'sk-sov-${secretHex.substring(0, 4)}...${secretHex.substring(secretHex.length - 4)}';

    final id =
        'key_${DateTime.now().microsecondsSinceEpoch}_${secureRandom.nextInt(999999)}';

    final metadata = ApiKeyMetadata(
      id: id,
      name: name.trim().isEmpty ? 'API Key' : name.trim(),
      keyPrefix: keyPrefix,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      isRevoked: false,
      permissions:
          permissions ??
          {ApiKeyPermission.chatCompletions, ApiKeyPermission.modelsList},
      rateLimitRpm: rateLimitRpm > 0 ? rateLimitRpm : 60,
      maxConcurrentRequests: maxConcurrentRequests > 0
          ? maxConcurrentRequests
          : 1,
      allowedModels: allowedModels,
      totalRequests: 0,
      saltHex: saltHex,
      hashHex: hashHex,
    );

    _keys.add(metadata);
    await _persist();
    notifyListeners();

    return GeneratedApiKeyResult(
      metadata: metadata,
      plaintextSecret: plaintextSecret,
    );
  }

  /// Immediately revokes a key. Revocation takes effect on the next request.
  Future<void> revokeKey(String id) async {
    await _ensureInitialized();
    final index = _keys.indexWhere((k) => k.id == id);
    if (index == -1) return;

    _keys[index] = _keys[index].copyWith(isRevoked: true);
    await _persist();
    notifyListeners();
  }

  /// Permanently deletes key metadata and hash.
  Future<void> deleteKey(String id) async {
    await _ensureInitialized();
    _keys.removeWhere((k) => k.id == id);
    _requestTimestamps.remove(id);
    _activeRequestCounts.remove(id);
    await _persist();
    notifyListeners();
  }

  /// Authenticates a Bearer token and enforces permissions, model allowlists, and rate limits.
  ///
  /// Constant-time comparison is used to prevent timing side-channel attacks.
  Future<AuthResult> authenticate(
    String? authHeader, {
    required ApiKeyPermission requiredPermission,
    String? requestedModel,
  }) async {
    await _ensureInitialized();

    if (authHeader == null || authHeader.trim().isEmpty) {
      return AuthResult.unauthorized(
        'Missing Authorization header. Expected: "Authorization: Bearer <API_KEY>"',
        code: 'missing_authorization_header',
      );
    }

    final trimmed = authHeader.trim();
    if (trimmed.toLowerCase() == 'bearer' ||
        authHeader.trimLeft().toLowerCase() == 'bearer ') {
      return AuthResult.unauthorized(
        'Empty Bearer token provided.',
        code: 'empty_api_key',
      );
    }
    if (!trimmed.startsWith('Bearer ') && !trimmed.startsWith('bearer ')) {
      return AuthResult.unauthorized(
        'Invalid Authorization format. Expected: "Bearer <API_KEY>"',
        code: 'invalid_authorization_format',
      );
    }

    final candidateSecret = trimmed.substring(7).trim();
    if (candidateSecret.isEmpty) {
      return AuthResult.unauthorized(
        'Empty Bearer token provided.',
        code: 'empty_api_key',
      );
    }

    // Verify secret against stored hashes using constant-time comparison
    ApiKeyMetadata? matchedKey;

    for (final key in _keys) {
      final computedHash = _computeHmac(candidateSecret, key.saltHex);
      if (_constantTimeEquals(computedHash, key.hashHex)) {
        matchedKey = key;
        break;
      }
    }

    if (matchedKey == null) {
      return AuthResult.unauthorized(
        'Incorrect or unknown API key provided.',
        code: 'invalid_api_key',
      );
    }

    // Check revocation
    if (matchedKey.isRevoked) {
      return AuthResult.unauthorized(
        'This API key has been revoked and can no longer be used.',
        code: 'revoked_api_key',
      );
    }

    // Check expiration
    if (matchedKey.isExpired) {
      return AuthResult.unauthorized(
        'This API key has expired.',
        code: 'expired_api_key',
      );
    }

    // Check permission
    if (!matchedKey.hasPermission(requiredPermission)) {
      return AuthResult.forbidden(
        'API key "${matchedKey.name}" lacks permission "${requiredPermission.id}".',
        code: 'insufficient_permissions',
      );
    }

    // Check model allowlist
    if (requestedModel != null && !matchedKey.isModelAllowed(requestedModel)) {
      return AuthResult.forbidden(
        'API key "${matchedKey.name}" is not permitted to access model "$requestedModel".',
        code: 'model_not_allowed',
      );
    }

    // Check rate limit (sliding 60-second window)
    final now = DateTime.now();
    final timestamps = _requestTimestamps.putIfAbsent(matchedKey.id, () => []);
    timestamps.removeWhere((ts) => now.difference(ts).inSeconds >= 60);

    if (timestamps.length >= matchedKey.rateLimitRpm) {
      final oldest = timestamps.first;
      final retryAfter = max(1, 60 - now.difference(oldest).inSeconds);
      return AuthResult.rateLimited(
        retryAfter,
        'Rate limit reached for API key "${matchedKey.name}" (${matchedKey.rateLimitRpm} req/min). Please retry in $retryAfter seconds.',
      );
    }

    // Check concurrency limit
    final activeCount = _activeRequestCounts[matchedKey.id] ?? 0;
    if (activeCount >= matchedKey.maxConcurrentRequests) {
      return AuthResult.concurrencyLimited(
        'Concurrent request limit reached for API key "${matchedKey.name}" (max: ${matchedKey.maxConcurrentRequests}).',
      );
    }

    return AuthResult.success(matchedKey);
  }

  /// Acquires an active in-flight request slot and updates key usage statistics.
  void acquireRequestSlot(String keyId) {
    _activeRequestCounts[keyId] = (_activeRequestCounts[keyId] ?? 0) + 1;
    final timestamps = _requestTimestamps.putIfAbsent(keyId, () => []);
    timestamps.add(DateTime.now());

    final index = _keys.indexWhere((k) => k.id == keyId);
    if (index != -1) {
      final key = _keys[index];
      _keys[index] = key.copyWith(
        totalRequests: key.totalRequests + 1,
        lastUsedAt: DateTime.now(),
      );
      // Persist async in background
      unawaited(_storage.saveKeys(_keys));
      notifyListeners();
    }
  }

  /// Releases the active in-flight request slot on request completion, error, or disconnect.
  void releaseRequestSlot(String keyId) {
    final current = _activeRequestCounts[keyId] ?? 0;
    if (current > 0) {
      _activeRequestCounts[keyId] = current - 1;
    }
  }

  int getInFlightCount(String keyId) => _activeRequestCounts[keyId] ?? 0;

  static String _computeHmac(String secret, String saltHex) {
    final hmac = Hmac(sha256, utf8.encode(saltHex));
    final digest = hmac.convert(utf8.encode(secret));
    return digest.toString();
  }

  /// Constant-time comparison between two hex strings to protect against timing side-channel attacks.
  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) {
      return false;
    }
    int result = 0;
    for (int i = 0; i < aBytes.length; i++) {
      result |= aBytes[i] ^ bBytes[i];
    }
    return result == 0;
  }

  Future<void> _persist() async {
    await _storage.saveKeys(_keys);
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }
}
