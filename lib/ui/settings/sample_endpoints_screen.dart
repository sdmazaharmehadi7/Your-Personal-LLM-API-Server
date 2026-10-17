import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../state/app_scope.dart';

class SampleEndpointsScreen extends StatefulWidget {
  final http.Client? httpClient;

  const SampleEndpointsScreen({super.key, this.httpClient});

  @override
  State<SampleEndpointsScreen> createState() => _SampleEndpointsScreenState();
}

class _SampleEndpointsScreenState extends State<SampleEndpointsScreen> {
  // Testing state for GET /v1/models
  bool _testingModels = false;
  int? _modelsStatusCode;
  String? _modelsResponse;
  int? _modelsLatencyMs;
  String? _modelsError;

  // Testing state for POST /v1/chat/completions
  bool _testingChat = false;
  int? _chatStatusCode;
  String? _chatResponse;
  String? _chatAssistantMessage;
  int? _chatLatencyMs;
  String? _chatError;

  // In-memory test key (if created on the fly)
  String? _sessionApiKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiServer = AppScope.apiServerOf(context);
    final remoteAccess = AppScope.remoteAccessOf(context);
    final modelState = AppScope.modelOf(context);

    final listenables = <Listenable>[?apiServer, ?remoteAccess, modelState];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final isServerRunning = apiServer?.isRunning ?? false;
        final lanIp = apiServer?.lanIp;
        final isExternal = apiServer?.allowExternalConnections == true;
        final configuredPort = apiServer?.configuredPort ?? 4891;

        final activeBaseUrl = isServerRunning
            ? (remoteAccess?.isConnected == true &&
                      remoteAccess?.publicHttpsUrl != null
                  ? '${remoteAccess!.publicHttpsUrl!}/v1'
                  : '${apiServer!.baseUrl}/v1')
            : (isExternal && lanIp != null
                  ? 'http://$lanIp:$configuredPort/v1'
                  : 'http://<device-ip>:$configuredPort/v1');

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Sample Endpoints'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                children: [
                  // Server Status Card (matching Screenshot 2 top card)
                  _buildServerStatusCard(
                    theme: theme,
                    isRunning: isServerRunning,
                    baseUrl: activeBaseUrl,
                  ),
                  const SizedBox(height: 24),

                  // How to Access Section
                  Text(
                    'How to Access',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The app runs a local HTTP server compatible with the OpenAI API format. '
                    'You can point any app, script, or tool (like LangChain or AutoGPT) to this Base URL.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Endpoint Card 1: GET /v1/models
                  _buildEndpointCard(
                    theme: theme,
                    method: 'GET',
                    methodColor: const Color(0xFF34D399),
                    methodBgColor: const Color(0xFF14291E),
                    path: '/v1/models',
                    description:
                        'List available models (currently loaded model).',
                    isLoading: _testingModels,
                    statusCode: _modelsStatusCode,
                    responseBody: _modelsResponse,
                    latencyMs: _modelsLatencyMs,
                    errorMessage: _modelsError,
                    onTest: isServerRunning ? _testModelsEndpoint : null,
                  ),
                  const SizedBox(height: 16),

                  // Endpoint Card 2: POST /v1/chat/completions
                  _buildEndpointCard(
                    theme: theme,
                    method: 'POST',
                    methodColor: const Color(0xFFFBBF24),
                    methodBgColor: const Color(0xFF2E2211),
                    path: '/v1/chat/completions',
                    description: 'Generate a chat completion. Accepts messages array in standard format.',
                    isLoading: _testingChat,
                    statusCode: _chatStatusCode,
                    responseBody: _chatResponse,
                    assistantMessage: _chatAssistantMessage,
                    latencyMs: _chatLatencyMs,
                    errorMessage: _chatError,
                    onTest: isServerRunning && modelState.hasLoadedModel
                        ? _testChatEndpoint
                        : null,
                    disabledTooltip: !isServerRunning
                        ? 'Start the local API server first'
                        : (!modelState.hasLoadedModel
                              ? 'Load a model in Model Manager first'
                              : null),
                  ),
                  const SizedBox(height: 24),

                  // Example Client Code snippets
                  _buildExampleSnippetCard(
                    theme: theme,
                    activeBaseUrl: activeBaseUrl,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Top Server Status Card (Green bordered container from Screenshot 2)
  Widget _buildServerStatusCard({
    required ThemeData theme,
    required bool isRunning,
    required String baseUrl,
  }) {
    final statusColor = isRunning
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final borderColor = isRunning
        ? const Color(0xFF1E3A2B)
        : const Color(0xFF3F1D1D);
    final bgColor = isRunning
        ? const Color(0xFF0F1E16)
        : const Color(0xFF1F1212);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isRunning ? Icons.check_circle : Icons.error_outline,
            color: statusColor,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRunning
                      ? 'Server Status: Running'
                      : 'Server Status: Stopped',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Base URL: $baseUrl',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          if (isRunning)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy Base URL',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: baseUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Base URL copied to clipboard!'),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Reusable Endpoint Card matching Screenshot 2 cards
  Widget _buildEndpointCard({
    required ThemeData theme,
    required String method,
    required Color methodColor,
    required Color methodBgColor,
    required String path,
    required String description,
    required bool isLoading,
    int? statusCode,
    String? responseBody,
    String? assistantMessage,
    int? latencyMs,
    String? errorMessage,
    VoidCallback? onTest,
    String? disabledTooltip,
  }) {
    final cardBgColor = const Color(0xFF181C26);
    final cardBorderColor = const Color(0xFF262B38);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Method badge, endpoint path, Test button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Method badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: methodBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      color: methodColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Endpoint path
                Expanded(
                  child: Text(
                    path,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                // Test button (purple/indigo matching Screenshot 2)
                Tooltip(
                  message:
                      disabledTooltip ??
                      'Send a test request to the running local server',
                  child: FilledButton(
                    onPressed: onTest,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Test',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF262B38)),
          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
          // Test Results Section (if executed)
          if (isLoading || statusCode != null || errorMessage != null) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFF262B38)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF12151D),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(11),
                ),
              ),
              child: _buildResponseSection(
                theme: theme,
                isLoading: isLoading,
                statusCode: statusCode,
                responseBody: responseBody,
                assistantMessage: assistantMessage,
                latencyMs: latencyMs,
                errorMessage: errorMessage,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResponseSection({
    required ThemeData theme,
    required bool isLoading,
    int? statusCode,
    String? responseBody,
    String? assistantMessage,
    int? latencyMs,
    String? errorMessage,
  }) {
    if (isLoading) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Executing request against local inference engine...'),
        ],
      );
    }

    if (errorMessage != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      );
    }

    final isSuccess =
        statusCode != null && statusCode >= 200 && statusCode < 300;
    final statusBadgeColor = isSuccess
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status code and latency
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusBadgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'HTTP $statusCode ${isSuccess ? 'OK' : 'Error'}',
                style: TextStyle(
                  color: statusBadgeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (latencyMs != null)
              Text(
                '${latencyMs}ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            const Spacer(),
            if (responseBody != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy JSON Response',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: responseBody));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Response copied to clipboard!'),
                    ),
                  );
                },
              ),
          ],
        ),
        if (assistantMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            'Assistant Output:',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              assistantMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        if (responseBody != null) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: SelectableText(
                responseBody,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExampleSnippetCard({
    required ThemeData theme,
    required String activeBaseUrl,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Quick Integration Example',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use this endpoint with any OpenAI SDK or standard HTTP client:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1218),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SelectableText(
                'curl $activeBaseUrl/chat/completions \\\n'
                '  -H "Authorization: Bearer <YOUR_API_KEY>" \\\n'
                '  -H "Content-Type: application/json" \\\n'
                '  -d \'{\n'
                '    "model": "loaded-model",\n'
                '    "messages": [{"role": "user", "content": "Hello!"}]\n'
                '  }\'',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Obtains or creates a temporary session API key to authenticate test requests.
  Future<String?> _getOrCreateTestApiKey() async {
    if (_sessionApiKey != null) return _sessionApiKey;

    final apiKeyService = AppScope.apiKeyServiceOf(context);
    if (apiKeyService == null) return null;

    // Create an ephemeral testing key
    final keyResult = await apiKeyService.createKey(
      name: 'Sample Endpoints Tester (Local UI)',
      rateLimitRpm: 120,
    );
    _sessionApiKey = keyResult.plaintextSecret;
    return _sessionApiKey;
  }

  /// Real execution of GET /v1/models
  Future<void> _testModelsEndpoint() async {
    final apiServer = AppScope.apiServerOf(context);
    if (apiServer == null || !apiServer.isRunning) {
      setState(() => _modelsError = 'Local API server is not running.');
      return;
    }

    setState(() {
      _testingModels = true;
      _modelsError = null;
      _modelsStatusCode = null;
      _modelsResponse = null;
    });

    final stopwatch = Stopwatch()..start();
    final client = widget.httpClient ?? http.Client();

    try {
      final apiKey = await _getOrCreateTestApiKey();
      final url = Uri.parse('${apiServer.baseUrl}/v1/models');
      final headers = <String, String>{
        if (apiKey != null) 'Authorization': 'Bearer $apiKey',
      };

      final response = await client
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      String formattedJson = response.body;
      try {
        final decoded = jsonDecode(response.body);
        formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}

      setState(() {
        _testingModels = false;
        _modelsStatusCode = response.statusCode;
        _modelsResponse = formattedJson;
        _modelsLatencyMs = stopwatch.elapsedMilliseconds;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _testingModels = false;
        _modelsError = 'Request failed: ${e.toString().split('\n').first}';
        _modelsLatencyMs = stopwatch.elapsedMilliseconds;
      });
    } finally {
      if (widget.httpClient == null) {
        client.close();
      }
    }
  }

  /// Real execution of POST /v1/chat/completions
  Future<void> _testChatEndpoint() async {
    final apiServer = AppScope.apiServerOf(context);
    final modelState = AppScope.modelOf(context);

    if (apiServer == null || !apiServer.isRunning) {
      setState(() => _chatError = 'Local API server is not running.');
      return;
    }

    if (!modelState.hasLoadedModel) {
      setState(() => _chatError = 'No model is currently loaded in memory.');
      return;
    }

    setState(() {
      _testingChat = true;
      _chatError = null;
      _chatStatusCode = null;
      _chatResponse = null;
      _chatAssistantMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    final client = widget.httpClient ?? http.Client();

    try {
      final apiKey = await _getOrCreateTestApiKey();
      final modelId =
          modelState.activeModel?.filename ??
          apiServer.coordinator.currentModelName ??
          'loaded-model';

      final url = Uri.parse('${apiServer.baseUrl}/v1/chat/completions');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (apiKey != null) 'Authorization': 'Bearer $apiKey',
      };

      final body = jsonEncode({
        'model': modelId,
        'messages': [
          {
            'role': 'user',
            'content': 'Respond with "Sovereign AI API is operational." in one sentence.',
          },
        ],
        'temperature': 0.7,
        'max_tokens': 32,
        'stream': false,
      });

      final response = await client
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
      stopwatch.stop();

      String formattedJson = response.body;
      String? assistantReply;

      try {
        final decoded = jsonDecode(response.body);
        formattedJson = const JsonEncoder.withIndent('  ').convert(decoded);
        if (decoded is Map &&
            decoded['choices'] is List &&
            (decoded['choices'] as List).isNotEmpty) {
          assistantReply = decoded['choices'][0]['message']?['content'];
        }
      } catch (_) {}

      setState(() {
        _testingChat = false;
        _chatStatusCode = response.statusCode;
        _chatResponse = formattedJson;
        _chatAssistantMessage = assistantReply;
        _chatLatencyMs = stopwatch.elapsedMilliseconds;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _testingChat = false;
        _chatError = 'Request failed: ${e.toString().split('\n').first}';
        _chatLatencyMs = stopwatch.elapsedMilliseconds;
      });
    } finally {
      if (widget.httpClient == null) {
        client.close();
      }
    }
  }
}
