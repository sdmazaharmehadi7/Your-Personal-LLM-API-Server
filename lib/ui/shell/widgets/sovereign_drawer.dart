import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/chat_session.dart';
import '../../../state/app_scope.dart';
import '../../diagnostics/diagnostics_screen.dart';

class SovereignDrawer extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectDestination;

  const SovereignDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelectDestination,
  });

  @override
  State<SovereignDrawer> createState() => _SovereignDrawerState();
}

class _SovereignDrawerState extends State<SovereignDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Enter new conversation title',
          ),
          onSubmitted: (val) {
            final trimmed = val.trim();
            if (trimmed.isNotEmpty) {
              AppScope.chatOf(context).renameSession(session.id, trimmed);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) {
                AppScope.chatOf(context).renameSession(session.id, trimmed);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ChatSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text('Are you sure you want to delete "${session.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              AppScope.chatOf(context).deleteSession(session.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = AppScope.chatOf(context);
    final modelState = AppScope.modelOf(context);
    final hasModelLoaded = modelState.hasLoadedModel;

    final sessions = chatState.sessions.where((s) {
      if (_filterQuery.isEmpty) return true;
      return s.title.toLowerCase().contains(_filterQuery.toLowerCase());
    }).toList();

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            // Header: Sovereign AI Branding
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConstants.appName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          hasModelLoaded
                              ? modelState.activeModel!.name
                              : '100% Offline & Private',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close sidebar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Prominent "+ New Chat" Action Button (ChatGPT Style)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerLow,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'New Chat',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onPressed: () {
                    chatState.createNewChat();
                    widget.onSelectDestination(0);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),

            // Search History Input
            if (chatState.sessions.length > 3 || _filterQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: TextField(
                  controller: _searchController,
                  style: theme.textTheme.bodySmall,
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _filterQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filterQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _filterQuery = val.trim());
                  },
                ),
              ),

            const SizedBox(height: 4),

            // Section Label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Conversations',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Chronological Conversations List
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                      child: Text(
                        _filterQuery.isNotEmpty
                            ? 'No chats match "$_filterQuery"'
                            : 'No saved chats yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final isActive =
                            session.id == chatState.activeSessionId &&
                            widget.selectedIndex == 0;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              chatState.selectSession(session.id);
                              widget.onSelectDestination(0);
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? theme.colorScheme.surfaceContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: isActive
                                    ? Border.all(
                                        color: theme.colorScheme.outlineVariant,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 16,
                                    color: isActive
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outline,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      session.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: isActive
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isActive
                                                ? theme.colorScheme.onSurface
                                                : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.85),
                                          ),
                                    ),
                                  ),
                                  Text(
                                    _formatSessionTime(session.updatedAt),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 16,
                                      color: theme.colorScheme.outline,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onSelected: (val) {
                                      if (val == 'rename') {
                                        _showRenameDialog(context, session);
                                      } else if (val == 'delete') {
                                        _confirmDelete(context, session);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 16),
                                            SizedBox(width: 8),
                                            Text('Rename'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Delete',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Bottom Navigation Links (Preserving all destinations)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: [
                  _buildDrawerNavItem(
                    context,
                    icon: Icons.dns_outlined,
                    label: 'Model Manager',
                    index: 1,
                  ),
                  _buildDrawerNavItem(
                    context,
                    icon: Icons.history_rounded,
                    label: 'Chat History',
                    index: 2,
                  ),
                  _buildDrawerNavItem(
                    context,
                    icon: Icons.tune_rounded,
                    label: 'Settings',
                    index: 3,
                  ),
                  _buildDrawerNavItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    label: 'About',
                    index: 4,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DiagnosticsScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              size: 18,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Diagnostics & Audit',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
  }) {
    final theme = Theme.of(context);
    final isSelected = widget.selectedIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          widget.onSelectDestination(index);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.surfaceContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
