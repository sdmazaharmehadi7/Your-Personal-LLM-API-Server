import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../models/chat_message.dart';
import '../../../models/rag/rag_citation.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCitationDetails(
    BuildContext context,
    RagCitation citation,
    int index,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.source_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Source [$index]: ${citation.fileName}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (citation.pageNumber != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Page ${citation.pageNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              Text(
                'Retrieved Evidence:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF18181B)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SelectableText(
                  citation.snippet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCitations(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final citations = message.citations!;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 13,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                'Sources:',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          for (int i = 0; i < citations.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showCitationDetails(context, citations[i], i + 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '[${i + 1}]',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        citations[i].fileName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (citations[i].pageNumber != null) ...[
                      const SizedBox(width: 2),
                      Text(
                        '(p.${citations[i].pageNumber})',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (message.role == MessageRole.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          constraints: const BoxConstraints(maxWidth: 680),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.6,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  message.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isUser = message.role == MessageRole.user;

    // ChatGPT / Claude style: User messages in compact right pill;
    // Assistant messages unboxed directly on canvas with avatar and copy actions.
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 48), // Indent from left
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF27272A) // Zinc 800
                      : const Color(0xFFF4F4F5), // Zinc 100
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: SelectableText(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.45,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant message (Unboxed, clean typographic flow)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    if (message.status == MessageStatus.generating &&
                        message.content.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thinking locally on device...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final displayText =
                        message.status == MessageStatus.generating
                        ? '${message.content} ▌'
                        : message.content;

                    if (message.status == MessageStatus.error) {
                      return SelectableText(
                        displayText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          height: 1.5,
                        ),
                      );
                    }

                    return MarkdownBody(
                      data: displayText,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.6,
                          fontSize: 15,
                          color: theme.colorScheme.onSurface,
                        ),
                        h1: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                        h2: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                        h3: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        code: TextStyle(
                          fontFamily: 'monospace',
                          backgroundColor: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFE4E4E7),
                          fontSize: 12.5,
                          color: isDark
                              ? const Color(0xFFF4F4F5)
                              : const Color(0xFF18181B),
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F0F11)
                              : const Color(0xFFF4F4F5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (message.citations != null && message.citations!.isNotEmpty)
                  _buildCitations(context),
                if (message.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.tokensPerSecond != null &&
                          message.tokensPerSecond! > 0) ...[
                        Icon(
                          Icons.speed,
                          size: 13,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${message.tokensPerSecond!.toStringAsFixed(1)} tok/s'
                          '${message.tokenCount != null ? ' (${message.tokenCount} tok)' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        tooltip: 'Copy response',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => _copyToClipboard(
                          context,
                          message.content,
                          'Response',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
