import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/responsive/responsive_layout.dart';
import '../../state/app_scope.dart';
import '../settings/sample_endpoints_screen.dart';

class LandingScreen extends StatefulWidget {
  final VoidCallback onNavigateToChat;
  final VoidCallback onNavigateToModels;
  final VoidCallback onNavigateToSettings;
  final VoidCallback? onOpenDrawer;

  const LandingScreen({
    super.key,
    required this.onNavigateToChat,
    required this.onNavigateToModels,
    required this.onNavigateToSettings,
    this.onOpenDrawer,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final TextEditingController _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _handleSubmitPrompt() {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

    final chatState = AppScope.chatOf(context);
    final modelState = AppScope.modelOf(context);
    final settingsState = AppScope.settingsOf(context);

    chatState.sendMessage(
      text,
      inferenceService: modelState.inferenceService,
      settings: settingsState.generationSettings,
      modelState: modelState,
    );
    _promptController.clear();
    widget.onNavigateToChat();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelState = AppScope.modelOf(context);
    final apiServer = AppScope.apiServerOf(context);
    final hasModelLoaded = modelState.hasLoadedModel;
    final isServerRunning = apiServer?.isRunning ?? false;
    final isDesktop = !ResponsiveLayout.isMobile(context);

    final activeModelName =
        modelState.activeModel?.name ??
        modelState.activeModel?.filename ??
        'No Model Loaded';

    final activePort =
        apiServer?.activePort ?? apiServer?.configuredPort ?? 8080;
    final serverUrl = isServerRunning
        ? (apiServer?.baseUrl ?? 'http://127.0.0.1:$activePort')
        : 'http://127.0.0.1:$activePort';

    const cardBgColor = Color(0xFF0F0F12);
    const cardBorderColor = Color(0xFF242428);
    const emeraldAccent = Color(0xFF10B981);
    const amberAccent = Color(0xFFF59E0B);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Conversations & Menu',
                onPressed: widget.onOpenDrawer,
              )
            : null,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Workstation',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cardBorderColor),
              ),
              child: const Text(
                'v1.0 Local',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Model status indicator
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onNavigateToModels,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: hasModelLoaded
                      ? const Color(0xFF14291E)
                      : const Color(0xFF23190B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasModelLoaded ? emeraldAccent : amberAccent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: hasModelLoaded ? emeraldAccent : amberAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      hasModelLoaded ? activeModelName : 'No Model Loaded',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasModelLoaded ? emeraldAccent : amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. HERO SECTION
                Container(
                  padding: EdgeInsets.all(isDesktop ? 32 : 20),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cardBorderColor, width: 1.2),
                    gradient: const RadialGradient(
                      center: Alignment(-0.8, -0.6),
                      radius: 1.2,
                      colors: [Color(0xFF1A1A22), Color(0xFF0F0F12)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: emeraldAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: emeraldAccent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 13,
                                  color: emeraldAccent,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '100% PRIVATE • ZERO TELEMETRY',
                                  style: TextStyle(
                                    color: emeraldAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Text(
                        'Sovereign AI',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: isDesktop ? 32 : 24,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Local & Offline Intelligence',
                        style: TextStyle(
                          fontSize: isDesktop ? 16 : 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Run GGUF language models directly on your Mac GPU with zero cloud dependencies. Chat privately with RAG document grounding, or expose an OpenAI-compatible HTTP server for Cursor, Continue, LangChain, and developer tooling.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Quick Prompt Input Box (ChatGPT Style)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF060608),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cardBorderColor,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _promptController,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                                decoration: const InputDecoration(
                                  hintText:
                                      'Ask Sovereign AI anything locally...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onSubmitted: (_) => _handleSubmitPrompt(),
                              ),
                            ),
                            Tooltip(
                              message: 'Send message',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 18,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: _handleSubmitPrompt,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 2. LIVE TELEMETRY TILES
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 650;
                    final children = [
                      // Tile 1: Model Status
                      _buildTelemetryCard(
                        context,
                        icon: Icons.memory_rounded,
                        title: 'Model Engine',
                        status: hasModelLoaded
                            ? activeModelName
                            : 'No Model Loaded',
                        statusColor: hasModelLoaded
                            ? emeraldAccent
                            : amberAccent,
                        subtitle: hasModelLoaded
                            ? 'Metal GPU accelerated runtime'
                            : 'Tap to select or import GGUF weights',
                        actionLabel: 'Manage',
                        onTap: widget.onNavigateToModels,
                      ),
                      // Tile 2: Local API Server
                      _buildTelemetryCard(
                        context,
                        icon: Icons.dns_rounded,
                        title: 'Local API Server',
                        status: isServerRunning
                            ? 'Online (Port $activePort)'
                            : 'Server Stopped',
                        statusColor: isServerRunning
                            ? emeraldAccent
                            : Colors.grey,
                        subtitle: isServerRunning
                            ? serverUrl
                            : 'OpenAI-compatible /v1 endpoints',
                        actionLabel: 'Configure',
                        onTap: widget.onNavigateToSettings,
                      ),
                      // Tile 3: Network & Security
                      _buildTelemetryCard(
                        context,
                        icon: Icons.security_rounded,
                        title: 'Network & Access',
                        status: apiServer?.allowExternalConnections ?? false
                            ? 'LAN (0.0.0.0)'
                            : 'Localhost (127.0.0.1)',
                        statusColor:
                            apiServer?.allowExternalConnections ?? false
                            ? amberAccent
                            : Colors.white,
                        subtitle: apiServer?.allowKeylessLocalhost ?? false
                            ? 'Keyless localhost enabled (like Ollama)'
                            : 'API key authentication active',
                        actionLabel: 'Security',
                        onTap: widget.onNavigateToSettings,
                      ),
                    ];

                    if (isWide) {
                      return Row(
                        children: children
                            .map(
                              (c) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: c,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    } else {
                      return Column(
                        children: children
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: c,
                              ),
                            )
                            .toList(),
                      );
                    }
                  },
                ),

                const SizedBox(height: 20),

                // 3. LAUNCHPAD CARDS (4 Main Workflows)
                Text(
                  'Quick Launchpad',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 550;
                    final card1 = _buildLaunchCard(
                      context,
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Private AI Chat',
                      description: 'Interactive streaming dialogue, conversation history, and RAG document grounding.',
                      buttonText: 'Open Chat',
                      onPressed: widget.onNavigateToChat,
                    );
                    final card2 = _buildLaunchCard(
                      context,
                      icon: Icons.dns_outlined,
                      title: 'Model Manager',
                      description: 'Download vetted GGUF models or import your own weights from local disk.',
                      buttonText: 'Open Models',
                      onPressed: widget.onNavigateToModels,
                    );
                    final card3 = _buildLaunchCard(
                      context,
                      icon: Icons.tune_rounded,
                      title: 'API Server & Settings',
                      description: 'Configure port, toggle LAN access, manage API keys, and manage tunnels.',
                      buttonText: 'Server Settings',
                      onPressed: widget.onNavigateToSettings,
                    );
                    final card4 = _buildLaunchCard(
                      context,
                      icon: Icons.terminal_rounded,
                      title: 'Sample Endpoints',
                      description: 'Live interactive testing for /v1/chat/completions and /v1/models with curl examples.',
                      buttonText: 'Test Endpoints',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SampleEndpointsScreen(),
                          ),
                        );
                      },
                    );

                    if (isWide) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: card1),
                              const SizedBox(width: 12),
                              Expanded(child: card2),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: card3),
                              const SizedBox(width: 12),
                              Expanded(child: card4),
                            ],
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          card1,
                          const SizedBox(height: 10),
                          card2,
                          const SizedBox(height: 10),
                          card3,
                          const SizedBox(height: 10),
                          card4,
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 24),

                // 4. QUICK-START TERMINAL CODE SNIPPET
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorderColor, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.terminal,
                            size: 18,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Quick Start Terminal Command',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            color: Colors.grey.shade400,
                            tooltip: 'Copy curl command',
                            onPressed: () {
                              const cmd =
                                  'curl -X POST http://127.0.0.1:8080/v1/chat/completions \\\n'
                                  '  -H "Content-Type: application/json" \\\n'
                                  '  -d \'{"model": "active-model", "messages": [{"role": "user", "content": "Hello Sovereign!"}]}\'';
                              Clipboard.setData(const ClipboardData(text: cmd));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'curl command copied to clipboard!',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF060608),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cardBorderColor),
                        ),
                        child: const SelectableText(
                          'curl -X POST http://127.0.0.1:8080/v1/chat/completions \\\n'
                          '  -H "Content-Type: application/json" \\\n'
                          '  -d \'{\n'
                          '    "model": "active-model",\n'
                          '    "messages": [{"role": "user", "content": "Hello Sovereign!"}]\n'
                          '  }\'',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFE2E8F0),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String status,
    required Color statusColor,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242428), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF242428), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF18181E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2E36)),
                ),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF141418),
                side: const BorderSide(color: Color(0xFF2E2E36)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
