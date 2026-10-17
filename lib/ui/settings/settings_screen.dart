import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'widgets/api_keys_card.dart';
import 'widgets/api_server_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _systemPromptController;

  @override
  void initState() {
    super.initState();
    _systemPromptController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AppScope.settingsOf(context).generationSettings;
    if (_systemPromptController.text != settings.systemPrompt) {
      _systemPromptController.text = settings.systemPrompt;
    }
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  String _getPlatformDescription() {
    if (kIsWeb) {
      return 'Web Browser (WebAssembly / Wasm environment)';
    }
    return '${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)} (${Platform.operatingSystemVersion})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsState = AppScope.settingsOf(context);
    final genSettings = settingsState.generationSettings;
    final storagePath =
        AppScope.storageOf(context).storageDirectoryPath ??
        '~/Library/Containers/sovereign_ai/models';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: () {
              settingsState.resetToDefaults();
              _systemPromptController.text =
                  settingsState.generationSettings.systemPrompt;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preferences reset to defaults')),
              );
            },
            child: const Text('Reset'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // Local API Server Section (Matching Screenshot 1)
              _buildApiServerHeader(theme),
              const SizedBox(height: 8),
              const ApiServerCard(),
              const SizedBox(height: 20),

              // API Key Management Section
              _buildSectionHeader('API Keys & Access Control', theme),
              const ApiKeysCard(),
              const SizedBox(height: 20),

              // Storage Section (Matching Screenshot 1)
              _buildSectionHeader('Storage', theme),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF181C26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF262B38)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      color: Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SelectableText(
                        storagePath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Danger Zone Section (Matching Screenshot 1)
              _buildSectionHeader('Danger Zone', theme),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFFEF4444),
                      width: 1.2,
                    ),
                    backgroundColor: const Color(0xFF181C26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                  label: const Text(
                    'Delete All Chats',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete All Chat Data?'),
                        content: const Text(
                          'This will permanently erase all local chat history. This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                            onPressed: () {
                              AppScope.chatOf(context).clearAllSessions();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('All chat history deleted.'),
                                ),
                              );
                            },
                            child: const Text('Delete All'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // Existing Appearance & Local Parameters Sections
              _buildSectionHeader('Appearance & Theme', theme),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Interface Theme',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto, size: 16),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode, size: 16),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode, size: 16),
                          ),
                        ],
                        selected: {settingsState.themeMode},
                        onSelectionChanged: (Set<ThemeMode> newSelection) {
                          settingsState.setThemeMode(newSelection.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _buildSectionHeader('Local Inference Parameters', theme),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sampling Temperature'),
                          Text(
                            genSettings.temperature.toStringAsFixed(2),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: genSettings.temperature,
                        min: 0.0,
                        max: 1.5,
                        divisions: 30,
                        label: genSettings.temperature.toStringAsFixed(2),
                        onChanged: (val) {
                          settingsState.updateGenerationSettings(
                            genSettings.copyWith(temperature: val),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Top-P (Nucleus Sampling)'),
                          Text(
                            genSettings.topP.toStringAsFixed(2),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: genSettings.topP,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        label: genSettings.topP.toStringAsFixed(2),
                        onChanged: (val) {
                          settingsState.updateGenerationSettings(
                            genSettings.copyWith(topP: val),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Max Generation Tokens'),
                          Text(
                            '${genSettings.maxTokens} tokens',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: genSettings.maxTokens.toDouble(),
                        min: 128,
                        max: 4096,
                        divisions: 31,
                        label: '${genSettings.maxTokens}',
                        onChanged: (val) {
                          settingsState.updateGenerationSettings(
                            genSettings.copyWith(maxTokens: val.round()),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Context Window Length'),
                          DropdownButton<int>(
                            value: genSettings.contextWindow,
                            items: const [
                              DropdownMenuItem(
                                value: 1024,
                                child: Text('1024'),
                              ),
                              DropdownMenuItem(
                                value: 2048,
                                child: Text('2048 (Standard)'),
                              ),
                              DropdownMenuItem(
                                value: 4096,
                                child: Text('4096'),
                              ),
                              DropdownMenuItem(
                                value: 8192,
                                child: Text('8192 (High RAM)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                settingsState.updateGenerationSettings(
                                  genSettings.copyWith(contextWindow: val),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('GPU Acceleration (Metal / Vulkan)'),
                        subtitle: Text(
                          'Offload model layers to hardware accelerator if supported.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        value: genSettings.useGpuAcceleration,
                        onChanged: (val) {
                          settingsState.updateGenerationSettings(
                            genSettings.copyWith(useGpuAcceleration: val),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Default System Prompt',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _systemPromptController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Enter default system instruction...',
                        ),
                        onChanged: (val) {
                          settingsState.updateGenerationSettings(
                            genSettings.copyWith(systemPrompt: val),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Hardware Diagnostics Link
              _buildSectionHeader('Diagnostics & Hardware Audit', theme),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.devices_outlined),
                        title: const Text('Current Host Platform'),
                        subtitle: Text(_getPlatformDescription()),
                      ),
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.analytics_outlined),
                        title: const Text(
                          'Hardware Diagnostics & System Audit',
                        ),
                        subtitle: const Text(
                          'View RAM recommendations, engine backend, and storage metrics',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DiagnosticsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApiServerHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Local API Server',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Expose the loaded model to OpenAI-compatible local clients.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.outline,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
