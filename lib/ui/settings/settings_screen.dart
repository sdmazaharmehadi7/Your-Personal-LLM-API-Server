import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../diagnostics/diagnostics_screen.dart';

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
            padding: const EdgeInsets.all(16),
            children: [
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
              const SizedBox(height: 24),
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
                          const Text('Context Window Length'),
                          DropdownButton<int>(
                            value: genSettings.contextWindow,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: 2048,
                                child: Text('2,048 tokens'),
                              ),
                              DropdownMenuItem(
                                value: 4096,
                                child: Text('4,096 tokens'),
                              ),
                              DropdownMenuItem(
                                value: 8192,
                                child: Text('8,192 tokens'),
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
              const SizedBox(height: 24),
              _buildSectionHeader('Storage & Hardware Environment', theme),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_special_outlined),
                        title: const Text('Storage Location'),
                        subtitle: const Text(
                          'Encrypted App Sandbox Storage (sovereign_ai/conversations.json, settings.json)',
                        ),
                      ),
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.wifi_off_outlined),
                        title: const Text('Telemetry & Analytics'),
                        subtitle: const Text(
                          'Disabled by design (100% offline)',
                        ),
                        trailing: Icon(
                          Icons.check_circle_outline,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          'Delete All Local Chat Data',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        subtitle: const Text(
                          'Erase all conversations and reset chat storage.',
                        ),
                        onTap: () {
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
                                        content: Text(
                                          'All chat history deleted.',
                                        ),
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
