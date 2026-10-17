import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/api_server/local_api_server.dart';
import '../../../state/app_scope.dart';
import '../sample_endpoints_screen.dart';

class ApiServerCard extends StatefulWidget {
  const ApiServerCard({super.key});

  @override
  State<ApiServerCard> createState() => _ApiServerCardState();
}

class _ApiServerCardState extends State<ApiServerCard> {
  late TextEditingController _portController;
  String? _portError;
  bool _isUpdatingExternal = false;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final apiServer = AppScope.apiServerOf(context);
    if (apiServer != null && _portController.text.isEmpty) {
      _portController.text = apiServer.configuredPort.toString();
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  void _validateAndSetPort(String val, LocalApiServer apiServer) {
    final parsed = int.tryParse(val.trim());
    if (parsed == null || parsed <= 0 || parsed > 65535) {
      setState(() => _portError = 'Invalid port (1 - 65535)');
      return;
    }
    setState(() => _portError = null);
    apiServer.setPort(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiServer = AppScope.apiServerOf(context);
    final remoteAccess = AppScope.remoteAccessOf(context);
    final modelState = AppScope.modelOf(context);

    if (apiServer == null) {
      return const SizedBox.shrink();
    }

    final listenables = <Listenable>[apiServer, ?remoteAccess, modelState];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final isServerRunning = apiServer.isRunning;
        final isServerTransitioning =
            apiServer.status == ApiServerStatus.starting ||
            apiServer.status == ApiServerStatus.stopping;
        final isTunnelConnected = remoteAccess?.isConnected ?? false;
        final isTunnelTransitioning =
            (remoteAccess?.isStarting ?? false) ||
            (remoteAccess?.isStopping ?? false);

        final isModelLoaded = modelState.hasLoadedModel;
        final activeModelName =
            modelState.activeModel?.name ??
            modelState.activeModel?.filename ??
            apiServer.coordinator.currentModelName ??
            '';

        final activeBaseUrl = isServerRunning
            ? '${apiServer.baseUrl}/v1'
            : (apiServer.allowExternalConnections && apiServer.lanIp != null
                  ? 'http://${apiServer.lanIp}:${apiServer.configuredPort}/v1'
                  : 'http://<device-ip>:${apiServer.configuredPort}/v1');

        const cardBgColor = Color(0xFF0F0F12);
        const cardBorderColor = Color(0xFF242428);
        const emeraldAccent = Color(0xFF10B981);
        const amberAccent = Color(0xFFF59E0B);

        return Container(
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorderColor, width: 1.2),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Local API Server Switch (Diamond Icon, Title, Subtitle, Switch)
              Row(
                children: [
                  // Sleek Obsidian Container with Chrome Icon
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2E36)),
                    ),
                    child: const Icon(
                      Icons.dns_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local API server',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'OpenAI base URL: $activeBaseUrl',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Emerald Online Toggle Switch
                  Switch(
                    value: isServerRunning,
                    activeThumbColor: Colors.white,
                    activeTrackColor: emeraldAccent,
                    inactiveThumbColor: Colors.grey.shade400,
                    inactiveTrackColor: Colors.grey.shade800,
                    onChanged: isServerTransitioning
                        ? null
                        : (val) async {
                            if (val) {
                              final parsedPort = int.tryParse(
                                _portController.text,
                              );
                              await apiServer.start(port: parsedPort);
                            } else {
                              await apiServer.stop();
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Row 2: Allow External Connections Switch
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Allow External Connections',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Listen on 0.0.0.0 instead of localhost',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Amber/Golden Toggle Switch
                  Switch(
                    value: apiServer.allowExternalConnections,
                    activeThumbColor: Colors.white,
                    activeTrackColor: amberAccent,
                    inactiveThumbColor: Colors.grey.shade400,
                    inactiveTrackColor: Colors.grey.shade800,
                    onChanged: (isServerTransitioning || _isUpdatingExternal)
                        ? null
                        : (val) async {
                            setState(() => _isUpdatingExternal = true);
                            try {
                              final success = await apiServer
                                  .setAllowExternalConnections(val);
                              if (!success &&
                                  context.mounted &&
                                  apiServer.errorMessage != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(apiServer.errorMessage!),
                                    backgroundColor: theme.colorScheme.error,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isUpdatingExternal = false);
                              }
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Row 3: Keyless Localhost Access Switch (Like Ollama)
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keyless Localhost Access',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Access from this Mac without an API key (like Ollama)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: apiServer.allowKeylessLocalhost,
                    activeThumbColor: Colors.white,
                    activeTrackColor: emeraldAccent,
                    inactiveThumbColor: Colors.grey.shade400,
                    inactiveTrackColor: Colors.grey.shade800,
                    onChanged: (val) {
                      apiServer.setAllowKeylessLocalhost(val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Warning Banner (matching Screenshot 1)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: apiServer.allowExternalConnections
                      ? const Color(0xFF23190B)
                      : const Color(0xFF141418),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: apiServer.allowExternalConnections
                        ? const Color(0xFF6B4310)
                        : const Color(0xFF242428),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      apiServer.allowExternalConnections
                          ? Icons.warning_amber_rounded
                          : Icons.security_outlined,
                      color: apiServer.allowExternalConnections
                          ? const Color(0xFFFBBF24)
                          : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anyone on your network can access your loaded model.',
                            style: TextStyle(
                              color: apiServer.allowExternalConnections
                                  ? const Color(0xFFFBBF24)
                                        .withValues(alpha: 0.95)
                                  : const Color(0xFFE2E8F0),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            apiServer.allowExternalConnections
                                ? 'The server is listening on 0.0.0.0. Other devices on your local network can connect to $activeBaseUrl with a valid API key.'
                                : 'Local-only mode is active (127.0.0.1). Enable external connections above to allow devices on your LAN to connect.',
                            style: TextStyle(
                              color: apiServer.allowExternalConnections
                                  ? const Color(0xFFFBBF24)
                                        .withValues(alpha: 0.75)
                                  : const Color(0xFF94A3B8),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Row 3: Model Loaded Status Pill + Base URL with Copy Button
              Row(
                children: [
                  // Model status pill badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isModelLoaded
                          ? const Color(0xFF14291E)
                          : const Color(0xFF2E2211),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isModelLoaded
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFBBF24),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      isModelLoaded
                          ? 'Model: $activeModelName'
                          : 'No model loaded',
                      style: TextStyle(
                        color: isModelLoaded
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFBBF24),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Base URL display
                  Expanded(
                    child: SelectableText(
                      activeBaseUrl,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isServerRunning
                            ? Colors.white
                            : Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isServerRunning)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copy Base URL',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: activeBaseUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Base URL copied to clipboard!'),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Row 4: Port Input Field with Subtext
              TextField(
                key: const Key('api_server_port_field'),
                controller: _portController,
                enabled: !isServerRunning && !isServerTransitioning,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: 'Port',
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  errorText: _portError,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF141418),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: cardBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: cardBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.white70,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (val) => _validateAndSetPort(val, apiServer),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Use your generated API key from below in clients that require one.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Row 5: Sample Endpoints & Testing Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SampleEndpointsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.terminal_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Sample Endpoints & Testing',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF141418),
                    side: const BorderSide(color: cardBorderColor, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Row 6: Internet Remote Access (Cloudflare HTTPS Tunnel - Separate from LAN)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141418),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_outlined,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Remote Access (HTTPS Tunnel)',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isTunnelConnected
                                    ? 'Tunnel active. Accessible from outside the local network.'
                                    : 'Access from outside local network via Cloudflare Tunnel.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isTunnelConnected,
                          activeThumbColor: Colors.white,
                          activeTrackColor: emeraldAccent,
                          inactiveThumbColor: Colors.grey.shade400,
                          inactiveTrackColor: Colors.grey.shade800,
                          onChanged: (!isServerRunning || isTunnelTransitioning)
                              ? null
                              : (val) async {
                                  if (val) {
                                    final success = await remoteAccess
                                        ?.startRemoteAccess();
                                    if (success != true && context.mounted) {
                                      final err =
                                          remoteAccess?.errorMessage ??
                                          'Failed to connect external tunnel.';
                                      if (err.contains(
                                        'cloudflared CLI not found',
                                      )) {
                                        _showCloudflaredSetupDialog(context);
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(err),
                                                backgroundColor:
                                                    theme.colorScheme.error,
                                              ),
                                            );
                                      }
                                    }
                                  } else {
                                    await remoteAccess?.stopRemoteAccess();
                                  }
                                },
                        ),
                      ],
                    ),
                    if (isTunnelConnected &&
                        remoteAccess?.publicHttpsUrl != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14291E),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF34D399)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                '${remoteAccess!.publicHttpsUrl!}/v1',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Color(0xFF34D399),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.copy,
                                size: 14,
                                color: Color(0xFF34D399),
                              ),
                              tooltip: 'Copy Public Tunnel URL',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: '${remoteAccess.publicHttpsUrl}/v1',
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Public HTTPS URL copied to clipboard!',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCloudflaredSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text('Cloudflare Tunnel Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To expose your Mac API over a secure, temporary HTTPS URL without port forwarding, Sovereign AI utilizes Cloudflare Quick Tunnels.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text(
              'Prerequisite Setup:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF242428)),
              ),
              child: const SelectableText(
                'brew install cloudflared',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'After installation completes in Terminal, toggle "Allow External Connections" again.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Command'),
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: 'brew install cloudflared'),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Copied "brew install cloudflared" to clipboard!',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
