import 'package:flutter/material.dart';

import '../../models/chat_session.dart';
import '../../state/app_scope.dart';
import '../common/empty_state_view.dart';

class ChatHistoryScreen extends StatelessWidget {
  final VoidCallback onNavigateToChat;

  const ChatHistoryScreen({super.key, required this.onNavigateToChat});

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Chat History?'),
        content: const Text(
          'This will permanently delete all conversations stored on your local device. This action cannot be undone.',
        ),
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
              AppScope.chatOf(context).clearAllSessions();
              Navigator.pop(ctx);
            },
            child: const Text('Delete All'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = AppScope.chatOf(context);
    final sessions = chatState.sessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat History'),
        actions: [
          if (sessions.isNotEmpty)
            IconButton(
              tooltip: 'Clear All History',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: () => _confirmClearAll(context),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: sessions.isEmpty
          ? EmptyStateView(
              icon: Icons.history_rounded,
              title: 'No Conversations Yet',
              description: 'Your local chat logs will appear here. No data is ever uploaded or synced to external servers.',
              action: FilledButton.tonalIcon(
                onPressed: () {
                  chatState.createNewChat();
                  onNavigateToChat();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Start New Conversation'),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isCurrent = session.id == chatState.activeSessionId;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isCurrent
                          ? (theme.brightness == Brightness.dark
                                ? const Color(0xFF202024)
                                : const Color(0xFFF4F4F5))
                          : theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: 0.4)
                              : theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${session.messages.length} messages • ${_formatDate(session.updatedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11.5,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              tooltip: 'Rename',
                              onPressed: () =>
                                  _showRenameDialog(context, session),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 17),
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(context, session),
                            ),
                          ],
                        ),
                        onTap: () {
                          chatState.selectSession(session.id);
                          onNavigateToChat();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
