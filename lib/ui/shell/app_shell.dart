import 'package:flutter/material.dart';

import '../../core/responsive/responsive_layout.dart';
import '../../state/app_scope.dart';
import '../about/about_screen.dart';
import '../chat/chat_screen.dart';
import '../history/chat_history_screen.dart';
import '../models/model_manager_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/sovereign_drawer.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktopOrTablet = !ResponsiveLayout.isMobile(context);
    final modelState = AppScope.modelOf(context);
    final hasModelLoaded = modelState.hasLoadedModel;

    final screens = [
      ChatScreen(
        onOpenModelManager: () => _onDestinationSelected(1),
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      const ModelManagerScreen(),
      ChatHistoryScreen(onNavigateToChat: () => _onDestinationSelected(0)),
      const SettingsScreen(),
      const AboutScreen(),
    ];

    if (isDesktopOrTablet) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: SovereignDrawer(
          selectedIndex: _selectedIndex,
          onSelectDestination: _onDestinationSelected,
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sovereign',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Tooltip(
                      message: hasModelLoaded
                          ? 'Active Model: ${modelState.activeModel!.name}'
                          : 'No Model Loaded',
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasModelLoaded
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasModelLoaded ? Icons.memory : Icons.memory_outlined,
                          size: 18,
                          color: hasModelLoaded ? Colors.green : Colors.amber,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: Text('Chat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.dns_outlined),
                  selectedIcon: Icon(Icons.dns),
                  label: Text('Models'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('History'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: Text('Settings'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: Text('About'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: screens),
            ),
          ],
        ),
      );
    }

    // Mobile layout with ChatGPT sidebar drawer and bottom NavigationBar
    return Scaffold(
      key: _scaffoldKey,
      drawer: SovereignDrawer(
        selectedIndex: _selectedIndex,
        onSelectDestination: _onDestinationSelected,
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Models',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'About',
          ),
        ],
      ),
    );
  }
}
