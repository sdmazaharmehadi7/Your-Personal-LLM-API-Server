import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../state/app_scope.dart';
import '../common/empty_state_view.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/no_model_banner.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback onOpenModelManager;
  final VoidCallback? onOpenDrawer;

  const ChatScreen({
    super.key,
    required this.onOpenModelManager,
    this.onOpenDrawer,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleAttachFiles() async {
    final chatState = AppScope.chatOf(context);
    final modelState = AppScope.modelOf(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'docx', 'csv', 'json', 'log'],
      );

      if (result.isEmpty) return;

      for (final file in result) {
        if (file.path != null) {
          try {
            await chatState.attachDocument(file.path!, modelState: modelState);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file picker: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showRenameDialog(BuildContext context, dynamic session) {
    final controller = TextEditingController(text: session.title as String);
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
              AppScope.chatOf(context)
                  .renameSession(session.id as String, trimmed);
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
                AppScope.chatOf(context)
                    .renameSession(session.id as String, trimmed);
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
    final modelState = AppScope.modelOf(context);
    final settingsState = AppScope.settingsOf(context);
    final activeSession = chatState.activeSession;
    final messages = activeSession?.messages ?? [];
    final hasModelLoaded = modelState.hasLoadedModel;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Conversations & Menu',
          icon: const Icon(Icons.menu_rounded, size: 22),
          onPressed: () {
            if (widget.onOpenDrawer != null) {
              widget.onOpenDrawer!();
            } else {
              Scaffold.of(context).openDrawer();
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              activeSession?.title ?? 'Sovereign AI',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            InkWell(
              onTap: widget.onOpenModelManager,
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: hasModelLoaded
                          ? const Color(0xFF10A37A)
                          : Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasModelLoaded
                        ? '${modelState.activeModel!.name} (Loaded)'
                        : 'No Model Loaded',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (activeSession != null)
            IconButton(
              tooltip: 'Rename Conversation',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showRenameDialog(context, activeSession),
            ),
          IconButton(
            tooltip: 'New Conversation',
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            onPressed: () {
              chatState.createNewChat();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (modelState.isLoading)
            LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainer,
            ),
          if (modelState.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      modelState.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: modelState.clearError,
                  ),
                ],
              ),
            ),
          if (!hasModelLoaded && !modelState.isLoading)
            NoModelBanner(onOpenModelManager: widget.onOpenModelManager),
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(context, hasModelLoaded)
                : _buildMessageList(messages, chatState.isGenerating),
          ),
          ChatInputBar(
            hasModelLoaded: hasModelLoaded,
            isGenerating: chatState.isGenerating,
            isIndexingDocument: chatState.isIndexingDocument,
            indexingDocumentName: chatState.indexingDocumentName,
            attachedDocuments: chatState.activeSessionDocuments,
            onAttachFiles: _handleAttachFiles,
            onRemoveAttachment: (docId) => chatState.removeDocument(docId),
            onSend: (text) {
              chatState.sendMessage(
                text,
                inferenceService: modelState.inferenceService,
                settings: settingsState.generationSettings,
                modelState: modelState,
              );
              _scrollToBottom();
            },
            onStop: () {
              chatState.stopGeneration(
                inferenceService: modelState.inferenceService,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool hasModelLoaded) {
    return EmptyStateView(
      icon: Icons.shield_outlined,
      title: 'Local & Offline Intelligence',
      description:
          'Your conversations, context, and prompts never leave this device. '
          'All computation is performed 100% locally using GGUF weights on your hardware.',
      action: !hasModelLoaded
          ? OutlinedButton.icon(
              onPressed: widget.onOpenModelManager,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Load a Local .gguf Model'),
            )
          : null,
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, bool isGenerating) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            return MessageBubble(message: messages[index]);
          },
        ),
      ),
    );
  }
}
