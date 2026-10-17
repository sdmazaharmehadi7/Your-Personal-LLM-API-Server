import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/api_key.dart';
import '../../models/chat_message.dart';
import '../../models/generation_settings.dart';
import '../inference_coordinator.dart';
import '../inference_service.dart';
import 'api_key_service.dart';

/// Lifecycle status of the local HTTP API server.
enum ApiServerStatus { stopped, starting, running, stopping, error }

/// A lightweight, local-only, OpenAI-compatible HTTP API server.
///
/// Binds strictly to loopback (`127.0.0.1`) and routes inference requests through
/// the authoritative [IInferenceCoordinator], ensuring that external HTTP clients
/// share the single in-memory model runtime without duplicate allocations.
///
/// All protected endpoints require a valid Bearer API key managed by [ApiKeyService].
class LocalApiServer extends ChangeNotifier {
  static int _requestCounter = 0;
  static const int maxRequestBodyBytes = 2 * 1024 * 1024; // 2MB safety limit

  final IInferenceCoordinator coordinator;
  final ApiKeyService apiKeyService;

  ApiServerStatus _status = ApiServerStatus.stopped;
  HttpServer? _server;
  String? _errorMessage;
  int _configuredPort = 8080;
  int? _activePort;
  bool _allowExternalConnections = false;
  bool _allowKeylessLocalhost = false;
  String? _lanIp;
  bool _isDisposed = false;

  static final ApiKeyMetadata _localhostKeylessMetadata = ApiKeyMetadata(
    id: 'localhost_keyless',
    name: 'Local Mac (Keyless)',
    keyPrefix: 'localhost',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    permissions: const {
      ApiKeyPermission.chatCompletions,
      ApiKeyPermission.modelsList,
    },
    rateLimitRpm: 10000,
    maxConcurrentRequests: 10,
    saltHex: '',
    hashHex: '',
  );

  LocalApiServer({
    required this.coordinator,
    ApiKeyService? apiKeyService,
    int initialPort = 8080,
    bool allowExternalConnections = false,
    bool allowKeylessLocalhost = false,
  }) : apiKeyService = apiKeyService ?? ApiKeyService(),
       _configuredPort = initialPort {
    _allowExternalConnections = allowExternalConnections;
    _allowKeylessLocalhost = allowKeylessLocalhost;
  }

  ApiServerStatus get status => _status;
  bool get isRunning => _status == ApiServerStatus.running;
  bool get isStopped => _status == ApiServerStatus.stopped;
  String? get errorMessage => _errorMessage;
  int get configuredPort => _configuredPort;
  int? get activePort => _activePort;

  /// Whether local requests from 127.0.0.1 on this Mac can access the API without an API key (like Ollama).
  bool get allowKeylessLocalhost => _allowKeylessLocalhost;

  /// Sets whether local requests from 127.0.0.1 can access the API without an API key.
  void setAllowKeylessLocalhost(bool allow) {
    if (_allowKeylessLocalhost == allow) return;
    _allowKeylessLocalhost = allow;
    if (!_isDisposed) notifyListeners();
  }

  /// Whether the server accepts connections from other devices on the LAN (binds to 0.0.0.0).
  ///
  /// When false, binds strictly to loopback (127.0.0.1).
  bool get allowExternalConnections => _allowExternalConnections;

  /// The detected local network IPv4 address (e.g. 192.168.1.10).
  String? get lanIp => _lanIp;

  /// The local loopback address.
  String get loopbackHost => '127.0.0.1';

  /// The client-facing host to connect to.
  ///
  /// When external connections are enabled, returns the actual LAN IP (e.g. 192.168.x.x).
  /// Never returns "0.0.0.0" as a client-facing host.
  String get host =>
      (_allowExternalConnections && _lanIp != null) ? _lanIp! : '127.0.0.1';

  /// The network address the server socket binds to.
  InternetAddress get bindAddress => _allowExternalConnections
      ? InternetAddress.anyIPv4
      : InternetAddress.loopbackIPv4;

  /// The base URL when running, or an empty string if stopped.
  String get baseUrl =>
      isRunning && _activePort != null ? 'http://$host:$_activePort' : '';

  /// Updates the configured port for future server starts.
  void setPort(int port) {
    if (port <= 0 || port > 65535) return;
    _configuredPort = port;
    if (!_isDisposed) notifyListeners();
  }

  /// Resolves the primary local network IPv4 address from available network interfaces.
  static Future<String?> getPrimaryLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // 1. Prioritize private IPv4 network ranges (RFC 1918)
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback &&
              !addr.isLinkLocal &&
              addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(ip)) {
              return ip;
            }
          }
        }
      }

      // 2. Fallback to any non-loopback IPv4 address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve LAN IP: $e');
    }
    return null;
  }

  /// Updates the cached LAN IP.
  Future<String?> resolveLanIp() async {
    final ip = await getPrimaryLanIp();
    if (ip != null) {
      _lanIp = ip;
    }
    return _lanIp;
  }

  /// Toggles whether external devices on the LAN can connect.
  ///
  /// If the server is currently running, stops and restarts with the new binding.
  Future<bool> setAllowExternalConnections(bool allow) async {
    if (_allowExternalConnections == allow) return true;
    _allowExternalConnections = allow;

    if (isRunning) {
      final currentPort = _activePort ?? _configuredPort;
      await stop();
      final success = await start(port: currentPort);
      return success;
    } else {
      if (allow) {
        await resolveLanIp();
      }
      if (!_isDisposed) notifyListeners();
      return true;
    }
  }

  /// Starts the HTTP API server.
  ///
  /// When [allowExternalConnections] or [_allowExternalConnections] is true,
  /// binds to `0.0.0.0` (all IPv4 interfaces) and resolves the Mac's LAN IP.
  /// When false, binds strictly to loopback (`127.0.0.1`).
  ///
  /// Idempotent: If already running or starting, returns immediately.
  Future<bool> start({int? port, bool? allowExternalConnections}) async {
    _checkNotDisposed();

    if (_status == ApiServerStatus.running ||
        _status == ApiServerStatus.starting) {
      return isRunning;
    }

    if (allowExternalConnections != null) {
      _allowExternalConnections = allowExternalConnections;
    }

    final targetPort = port ?? _configuredPort;
    _setStatus(ApiServerStatus.starting);
    _errorMessage = null;

    try {
      // Ensure API key service is initialized before serving requests
      await apiKeyService.init();

      // If external connections are enabled, resolve real LAN IP for client URL display
      if (_allowExternalConnections) {
        await resolveLanIp();
      }

      final addressToBind = bindAddress;
      final server = await HttpServer.bind(
        addressToBind,
        targetPort,
        shared: false,
      );

      _server = server;
      _activePort = server.port;
      _configuredPort = server.port;
      _setStatus(ApiServerStatus.running);

      server.listen(
        _handleRequest,
        onError: (Object error) {
          if (!_isDisposed && _status == ApiServerStatus.running) {
            _errorMessage = 'HTTP server error: $error';
            _setStatus(ApiServerStatus.error);
          }
        },
        onDone: () {
          if (!_isDisposed && _status == ApiServerStatus.running) {
            _setStatus(ApiServerStatus.stopped);
          }
        },
        cancelOnError: false,
      );

      return true;
    } on SocketException catch (e) {
      _server = null;
      _activePort = null;
      final boundName = _allowExternalConnections ? '0.0.0.0' : '127.0.0.1';
      _errorMessage = 'Failed to bind to $boundName:$targetPort. ${e.message}';
      _setStatus(ApiServerStatus.error);
      return false;
    } catch (e) {
      _server = null;
      _activePort = null;
      _errorMessage =
          'Unexpected server startup failure: ${e.toString().split('\n').first}';
      _setStatus(ApiServerStatus.error);
      return false;
    }
  }

  /// Stops the HTTP API server and releases the listening socket.
  ///
  /// Idempotent: Safe to call repeatedly. Does not unload GGUF weights or wipe data.
  Future<void> stop() async {
    if (_isDisposed) return;
    if (_status == ApiServerStatus.stopped ||
        _status == ApiServerStatus.stopping) {
      return;
    }

    _setStatus(ApiServerStatus.stopping);

    try {
      if (_server != null) {
        await _server!.close(force: true);
        _server = null;
      }
      _activePort = null;
      _setStatus(ApiServerStatus.stopped);
    } catch (e) {
      _errorMessage = 'Error while stopping server: $e';
      _setStatus(ApiServerStatus.error);
    }
  }

  /// Request routing and handling.
  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers for local developer tooling
    _applyCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (request.method == 'GET' && path == '/health') {
        await _handleHealth(request);
      } else if (request.method == 'GET' &&
          (path == '/v1/models' || path == '/models')) {
        await _handleListModels(request);
      } else if (request.method == 'POST' &&
          (path == '/v1/chat/completions' || path == '/chat/completions')) {
        await _handleChatCompletions(request);
      } else {
        _sendError(
          request.response,
          statusCode: HttpStatus.notFound,
          message:
              'Endpoint "$path" not found on Sovereign AI Local API Server.',
          type: 'invalid_request_error',
          code: 'resource_not_found',
        );
      }
    } catch (e) {
      _sendError(
        request.response,
        statusCode: HttpStatus.internalServerError,
        message: 'Internal server error processing request.',
        type: 'api_error',
        code: 'internal_error',
      );
    }
  }

  /// GET /health
  ///
  /// Public on localhost for readiness and monitoring checks.
  /// Reports server status, active model state, and queue length without exposing disk paths or secrets.
  Future<void> _handleHealth(HttpRequest request) async {
    final isModelLoaded = coordinator.isLoaded;
    final modelName = coordinator.currentModelName;

    final body = {
      'status': 'ok',
      'server': 'sovereign_ai_local_server',
      'version': '1.0.0',
      'model_loaded': isModelLoaded,
      'active_model': modelName,
      'queue_length': coordinator.queueLength,
      'is_generating': coordinator.isGenerating,
      'authenticated': true,
      'binding': 'localhost_only',
    };

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  /// Checks whether an HTTP request originates purely from the local Mac loopback interface
  /// and not forwarded via a remote reverse proxy or tunnel.
  bool _isLocalhostOnlyRequest(HttpRequest request) {
    final remoteAddr = request.connectionInfo?.remoteAddress;
    final isLoopback =
        remoteAddr != null &&
        (remoteAddr.isLoopback ||
            remoteAddr.address == '127.0.0.1' ||
            remoteAddr.address == '::1');

    // Tunnel and remote proxy traffic forwarded via loopback carries proxy headers
    final hasTunnelHeaders =
        request.headers.value('cf-connecting-ip') != null ||
        request.headers.value('cf-ray') != null ||
        request.headers.value('x-forwarded-for') != null;

    return isLoopback && !hasTunnelHeaders;
  }

  /// Authenticates incoming requests, granting keyless access for local Mac requests
  /// if [_allowKeylessLocalhost] is enabled (similar to Ollama).
  Future<AuthResult> _authenticateRequest(
    HttpRequest request, {
    required ApiKeyPermission requiredPermission,
  }) async {
    final authHeader = request.headers.value(HttpHeaders.authorizationHeader);

    if (_allowKeylessLocalhost && _isLocalhostOnlyRequest(request)) {
      if (authHeader == null ||
          authHeader == 'Bearer local' ||
          authHeader == 'Bearer ollama' ||
          authHeader.trim().isEmpty) {
        return AuthResult.success(_localhostKeylessMetadata);
      }
    }

    return await apiKeyService.authenticate(
      authHeader,
      requiredPermission: requiredPermission,
    );
  }

  /// GET /v1/models
  ///
  /// Authenticated: Returns an OpenAI-compatible list of available models.
  Future<void> _handleListModels(HttpRequest request) async {
    // Authenticate with required permission
    final authResult = await _authenticateRequest(
      request,
      requiredPermission: ApiKeyPermission.modelsList,
    );

    if (!authResult.isSuccess) {
      final headers = <String, String>{};
      if (authResult.retryAfterSeconds != null) {
        headers[HttpHeaders.retryAfterHeader] = authResult.retryAfterSeconds
            .toString();
      }
      _sendError(
        request.response,
        statusCode: authResult.statusCode,
        message: authResult.errorMessage ?? 'Authentication failed.',
        type: authResult.statusCode == HttpStatus.tooManyRequests
            ? 'rate_limit_error'
            : 'invalid_request_error',
        code: authResult.errorCode,
        headers: headers,
      );
      return;
    }

    final keyId = authResult.key!.id;
    apiKeyService.acquireRequestSlot(keyId);

    try {
      final List<Map<String, dynamic>> modelsData = [];

      if (coordinator.isLoaded) {
        final modelId =
            coordinator.currentModelName ??
            coordinator.activeModel?.id ??
            'loaded-model';

        // Check if this model is allowed for this key
        if (authResult.key!.isModelAllowed(modelId)) {
          modelsData.add({
            'id': modelId,
            'object': 'model',
            'created':
                coordinator.activeModel?.lastUsedAt?.millisecondsSinceEpoch ??
                1700000000,
            'owned_by': coordinator.activeModel?.publisher ?? 'local',
            'permission': <Map<String, dynamic>>[],
            'root': modelId,
            'parent': null,
          });
        }
      }

      final body = {'object': 'list', 'data': modelsData};

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    } finally {
      apiKeyService.releaseRequestSlot(keyId);
    }
  }

  /// POST /v1/chat/completions
  ///
  /// Authenticated: OpenAI-compatible chat completions with streaming SSE and non-streaming responses.
  Future<void> _handleChatCompletions(HttpRequest request) async {
    // 1. Initial Authentication check (before reading payload or coordinator queue)
    final authResult = await _authenticateRequest(
      request,
      requiredPermission: ApiKeyPermission.chatCompletions,
    );

    if (!authResult.isSuccess) {
      final headers = <String, String>{};
      if (authResult.retryAfterSeconds != null) {
        headers[HttpHeaders.retryAfterHeader] = authResult.retryAfterSeconds
            .toString();
      }
      _sendError(
        request.response,
        statusCode: authResult.statusCode,
        message: authResult.errorMessage ?? 'Authentication failed.',
        type: authResult.statusCode == HttpStatus.tooManyRequests
            ? 'rate_limit_error'
            : 'invalid_request_error',
        code: authResult.errorCode,
        headers: headers,
      );
      return;
    }

    final matchedKey = authResult.key!;

    // 2. Read and enforce request body size
    if (request.contentLength > maxRequestBodyBytes) {
      _sendError(
        request.response,
        statusCode: HttpStatus.requestEntityTooLarge,
        message:
            'Request payload exceeds maximum allowed size (${maxRequestBodyBytes ~/ (1024 * 1024)}MB).',
        type: 'invalid_request_error',
        code: 'request_too_large',
      );
      try {
        await request.drain().catchError((_) {});
      } catch (_) {}
      return;
    }

    final rawBytes = <int>[];
    await for (final chunk in request) {
      rawBytes.addAll(chunk);
      if (rawBytes.length > maxRequestBodyBytes) {
        _sendError(
          request.response,
          statusCode: HttpStatus.requestEntityTooLarge,
          message:
              'Request payload exceeds maximum allowed size (${maxRequestBodyBytes ~/ (1024 * 1024)}MB).',
          type: 'invalid_request_error',
          code: 'request_too_large',
        );
        try {
          await request.drain().catchError((_) {});
        } catch (_) {}
        return;
      }
    }

    if (rawBytes.isEmpty) {
      _sendError(
        request.response,
        statusCode: HttpStatus.badRequest,
        message: 'Request body must not be empty.',
        type: 'invalid_request_error',
        code: 'empty_body',
      );
      return;
    }

    // 3. Verify model is loaded
    if (!coordinator.isLoaded) {
      _sendError(
        request.response,
        statusCode: HttpStatus.serviceUnavailable,
        message:
            'No GGUF model is currently loaded in memory. '
            'Please load a model in the Sovereign AI desktop application before sending inference requests.',
        type: 'server_error',
        code: 'model_not_loaded',
      );
      return;
    }

    // 4. Parse JSON
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(rawBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Root must be an object');
      }
      payload = decoded;
    } catch (_) {
      _sendError(
        request.response,
        statusCode: HttpStatus.badRequest,
        message: 'Malformed JSON syntax in request body.',
        type: 'invalid_request_error',
        code: 'invalid_json',
      );
      return;
    }

    // 5. Validate requested model
    final requestedModel = payload['model'];
    if (requestedModel == null ||
        requestedModel is! String ||
        requestedModel.trim().isEmpty) {
      _sendError(
        request.response,
        statusCode: HttpStatus.badRequest,
        message: 'Missing or empty "model" parameter.',
        type: 'invalid_request_error',
        param: 'model',
        code: 'missing_model',
      );
      return;
    }

    final activeName = coordinator.currentModelName ?? '';
    final activeId = coordinator.activeModel?.id ?? '';
    final trimmedModel = requestedModel.trim().toLowerCase();

    final matchesActive =
        trimmedModel == 'default' ||
        trimmedModel == 'local' ||
        trimmedModel == activeName.toLowerCase() ||
        trimmedModel == activeId.toLowerCase() ||
        trimmedModel == activeName.replaceAll('.gguf', '').toLowerCase();

    if (!matchesActive) {
      _sendError(
        request.response,
        statusCode: HttpStatus.notFound,
        message:
            'Model "$requestedModel" is not loaded. The currently active model is "$activeName". '
            'Sovereign AI runs a single model in memory to conserve hardware resources.',
        type: 'invalid_request_error',
        param: 'model',
        code: 'model_not_found',
      );
      return;
    }

    // 6. Check per-key model restriction
    if (!matchedKey.isModelAllowed(requestedModel)) {
      _sendError(
        request.response,
        statusCode: HttpStatus.forbidden,
        message:
            'API key "${matchedKey.name}" is not permitted to access model "$requestedModel".',
        type: 'invalid_request_error',
        param: 'model',
        code: 'model_not_allowed',
      );
      return;
    }

    // 7. Validate messages
    final rawMessages = payload['messages'];
    if (rawMessages == null || rawMessages is! List || rawMessages.isEmpty) {
      _sendError(
        request.response,
        statusCode: HttpStatus.badRequest,
        message: '"messages" must be a non-empty array of message objects.',
        type: 'invalid_request_error',
        param: 'messages',
        code: 'invalid_messages',
      );
      return;
    }

    final chatMessages = <ChatMessage>[];
    int msgIndex = 0;
    for (final rawMsg in rawMessages) {
      if (rawMsg is! Map) {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: 'Message at index $msgIndex must be a JSON object.',
          type: 'invalid_request_error',
          param: 'messages[$msgIndex]',
          code: 'invalid_message_structure',
        );
        return;
      }

      final roleStr = rawMsg['role'];
      final contentRaw = rawMsg['content'];

      if (roleStr == null || roleStr is! String) {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: 'Message at index $msgIndex missing valid "role".',
          type: 'invalid_request_error',
          param: 'messages[$msgIndex].role',
          code: 'missing_role',
        );
        return;
      }

      final MessageRole role;
      switch (roleStr.toLowerCase()) {
        case 'system':
          role = MessageRole.system;
          break;
        case 'user':
          role = MessageRole.user;
          break;
        case 'assistant':
          role = MessageRole.assistant;
          break;
        default:
          _sendError(
            request.response,
            statusCode: HttpStatus.badRequest,
            message:
                'Unsupported message role "$roleStr". Supported roles: system, user, assistant.',
            type: 'invalid_request_error',
            param: 'messages[$msgIndex].role',
            code: 'unsupported_role',
          );
          return;
      }

      final String content;
      if (contentRaw is String) {
        content = contentRaw;
      } else if (contentRaw is List) {
        content = contentRaw
            .whereType<Map>()
            .where((p) => p['type'] == 'text' && p['text'] is String)
            .map((p) => p['text'] as String)
            .join('\n');
      } else {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: 'Message content at index $msgIndex must be a string.',
          type: 'invalid_request_error',
          param: 'messages[$msgIndex].content',
          code: 'invalid_content',
        );
        return;
      }

      chatMessages.add(
        ChatMessage(
          id: 'api_${DateTime.now().microsecondsSinceEpoch}_${msgIndex++}',
          role: role,
          content: content,
          timestamp: DateTime.now(),
        ),
      );
    }

    // 8. Optional parameters validation
    double temperature = 0.7;
    if (payload.containsKey('temperature') && payload['temperature'] != null) {
      final t = payload['temperature'];
      if (t is! num || t < 0.0 || t > 2.0) {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '"temperature" must be a number between 0.0 and 2.0.',
          type: 'invalid_request_error',
          param: 'temperature',
          code: 'invalid_temperature',
        );
        return;
      }
      temperature = t.toDouble();
    }

    double topP = 0.9;
    if (payload.containsKey('top_p') && payload['top_p'] != null) {
      final tp = payload['top_p'];
      if (tp is! num || tp < 0.0 || tp > 1.0) {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '"top_p" must be a number between 0.0 and 1.0.',
          type: 'invalid_request_error',
          param: 'top_p',
          code: 'invalid_top_p',
        );
        return;
      }
      topP = tp.toDouble();
    }

    int maxTokens = 2048;
    if (payload.containsKey('max_tokens') && payload['max_tokens'] != null) {
      final mt = payload['max_tokens'];
      if (mt is! int || mt <= 0) {
        _sendError(
          request.response,
          statusCode: HttpStatus.badRequest,
          message: '"max_tokens" must be a positive integer.',
          type: 'invalid_request_error',
          param: 'max_tokens',
          code: 'invalid_max_tokens',
        );
        return;
      }
      maxTokens = mt;
    }

    final isStreaming = payload['stream'] == true;

    final settings = GenerationSettings(
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
    );

    // Acquire request slot for rate limit & concurrency tracking
    apiKeyService.acquireRequestSlot(matchedKey.id);

    // 9. Acquire inference via shared coordinator with unique HTTP requestId
    final requestId =
        'http_req_${DateTime.now().microsecondsSinceEpoch}_${++_requestCounter}';
    final createdTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Stream<String> tokenStream;
    try {
      tokenStream = await coordinator.generate(
        messages: chatMessages,
        settings: settings,
        requestId: requestId,
      );
    } on InferenceQueueFullException catch (e) {
      apiKeyService.releaseRequestSlot(matchedKey.id);
      _sendError(
        request.response,
        statusCode: HttpStatus.tooManyRequests,
        message: e.message,
        type: 'rate_limit_error',
        code: 'queue_full',
      );
      return;
    } on InferenceModelNotLoadedException catch (e) {
      apiKeyService.releaseRequestSlot(matchedKey.id);
      _sendError(
        request.response,
        statusCode: HttpStatus.serviceUnavailable,
        message: e.message,
        type: 'server_error',
        code: 'model_not_loaded',
      );
      return;
    } on InferenceException catch (e) {
      apiKeyService.releaseRequestSlot(matchedKey.id);
      _sendError(
        request.response,
        statusCode: HttpStatus.serviceUnavailable,
        message: e.message,
        type: 'server_error',
        code: 'inference_error',
      );
      return;
    }

    // Client disconnect hook: If connection drops, cancel this request and release slot
    unawaited(
      request.response.done.then(
        (_) {
          apiKeyService.releaseRequestSlot(matchedKey.id);
        },
        onError: (_) {
          apiKeyService.releaseRequestSlot(matchedKey.id);
          coordinator.cancelRequest(requestId);
        },
      ),
    );

    if (isStreaming) {
      await _streamResponse(
        response: request.response,
        tokenStream: tokenStream,
        requestId: requestId,
        modelName: activeName,
        createdSecs: createdTimestamp,
        onClientDisconnect: () {
          apiKeyService.releaseRequestSlot(matchedKey.id);
          coordinator.cancelRequest(requestId);
        },
      );
    } else {
      await _nonStreamingResponse(
        response: request.response,
        tokenStream: tokenStream,
        requestId: requestId,
        modelName: activeName,
        createdSecs: createdTimestamp,
        messages: chatMessages,
        onComplete: () {
          apiKeyService.releaseRequestSlot(matchedKey.id);
        },
      );
    }
  }

  /// Sends a non-streaming OpenAI-compatible completion.
  Future<void> _nonStreamingResponse({
    required HttpResponse response,
    required Stream<String> tokenStream,
    required String requestId,
    required String modelName,
    required int createdSecs,
    required List<ChatMessage> messages,
    required VoidCallback onComplete,
  }) async {
    final buffer = StringBuffer();
    int completionTokens = 0;

    try {
      await for (final token in tokenStream) {
        buffer.write(token);
        completionTokens++;
      }

      // Simple, honest heuristic: ~4 chars per token for estimated prompt tokens
      final promptText = messages.map((m) => m.content).join(' ');
      final estimatedPromptTokens = (promptText.length / 4).ceil();

      final responseBody = {
        'id': 'chatcmpl-$requestId',
        'object': 'chat.completion',
        'created': createdSecs,
        'model': modelName,
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': buffer.toString()},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': estimatedPromptTokens,
          'completion_tokens': completionTokens,
          'total_tokens': estimatedPromptTokens + completionTokens,
          'estimated': true,
        },
      };

      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(responseBody));
      await response.close();
    } catch (e) {
      _sendError(
        response,
        statusCode: HttpStatus.internalServerError,
        message: 'Inference interrupted: ${e.toString().split('\n').first}',
        type: 'api_error',
        code: 'inference_interrupted',
      );
    } finally {
      onComplete();
    }
  }

  /// Streams token deltas formatted as standard Server-Sent Events (SSE).
  Future<void> _streamResponse({
    required HttpResponse response,
    required Stream<String> tokenStream,
    required String requestId,
    required String modelName,
    required int createdSecs,
    required VoidCallback onClientDisconnect,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set(
      HttpHeaders.cacheControlHeader,
      'no-cache, no-transform',
    );
    response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

    try {
      // 1. Initial role chunk
      final initialChunk = {
        'id': 'chatcmpl-$requestId',
        'object': 'chat.completion.chunk',
        'created': createdSecs,
        'model': modelName,
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': ''},
            'finish_reason': null,
          },
        ],
      };
      response.write('data: ${jsonEncode(initialChunk)}\n\n');
      await response.flush();

      // 2. Stream tokens
      await for (final token in tokenStream) {
        final chunk = {
          'id': 'chatcmpl-$requestId',
          'object': 'chat.completion.chunk',
          'created': createdSecs,
          'model': modelName,
          'choices': [
            {
              'index': 0,
              'delta': {'content': token},
              'finish_reason': null,
            },
          ],
        };
        response.write('data: ${jsonEncode(chunk)}\n\n');
        await response.flush();
      }

      // 3. Final stop reason chunk
      final stopChunk = {
        'id': 'chatcmpl-$requestId',
        'object': 'chat.completion.chunk',
        'created': createdSecs,
        'model': modelName,
        'choices': [
          {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
        ],
      };
      response.write('data: ${jsonEncode(stopChunk)}\n\n');

      // 4. OpenAI standard SSE termination
      response.write('data: [DONE]\n\n');
      await response.flush();
      await response.close();
    } catch (_) {
      onClientDisconnect();
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Sends a structured JSON error according to the OpenAI error spec.
  /// Never echoes submitted authorization headers or internal hashes.
  void _sendError(
    HttpResponse response, {
    required int statusCode,
    required String message,
    required String type,
    String? code,
    String? param,
    Map<String, String>? headers,
  }) {
    try {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      if (headers != null) {
        headers.forEach((key, val) {
          response.headers.set(key, val);
        });
      }
      final errorMap = <String, dynamic>{'message': message, 'type': type};
      if (param != null) errorMap['param'] = param;
      if (code != null) errorMap['code'] = code;
      response.write(jsonEncode({'error': errorMap}));
      unawaited(response.close().catchError((_) {}));
    } catch (_) {}
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Requested-With',
    );
  }

  void _setStatus(ApiServerStatus newStatus) {
    _status = newStatus;
    if (!_isDisposed) notifyListeners();
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('LocalApiServer has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _server?.close(force: true);
    _server = null;
    super.dispose();
  }
}
