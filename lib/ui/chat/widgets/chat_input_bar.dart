import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/rag/document_attachment.dart';

class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback? onStop;
  final VoidCallback? onAttachFiles;
  final ValueChanged<String>? onRemoveAttachment;
  final List<DocumentAttachment> attachedDocuments;
  final bool isIndexingDocument;
  final String? indexingDocumentName;
  final bool isGenerating;
  final bool hasModelLoaded;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onStop,
    this.onAttachFiles,
    this.onRemoveAttachment,
    this.attachedDocuments = const [],
    this.isIndexingDocument = false,
    this.indexingDocumentName,
    this.isGenerating = false,
    this.hasModelLoaded = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() {
      final hasTextNow = _controller.text.trim().isNotEmpty;
      if (hasTextNow != _hasText) {
        setState(() {
          _hasText = hasTextNow;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isGenerating) return;
    widget.onSend(text);
    _controller.clear();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildAttachmentChips(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final chips = <Widget>[];

    // Show indexing progress pill if currently indexing
    if (widget.isIndexingDocument) {
      chips.add(
        Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
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
                'Indexing ${widget.indexingDocumentName ?? "document"}...',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show already attached documents
    for (final doc in widget.attachedDocuments) {
      final isError = doc.status == DocumentStatus.error;
      final ext = doc.fileExtension.toUpperCase();

      chips.add(
        Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: isError
                ? theme.colorScheme.error.withValues(alpha: 0.1)
                : (isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isError
                  ? theme.colorScheme.error.withValues(alpha: 0.4)
                  : theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : (ext == 'PDF'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.description_outlined),
                size: 15,
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  doc.fileName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_formatFileSize(doc.fileSizeBytes)})',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.isGenerating
                    ? null
                    : () => widget.onRemoveAttachment?.call(doc.id),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: chips),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAttachmentChips(context),
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (_hasText && !widget.isGenerating) {
                        _handleSend();
                      }
                    },
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Document Attachment paperclip button
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.attach_file_rounded,
                                size: 20,
                                color:
                                    widget.isGenerating ||
                                        widget.isIndexingDocument
                                    ? theme.colorScheme.outline.withValues(
                                        alpha: 0.4,
                                      )
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              tooltip: 'Attach document (PDF, DOCX, TXT, MD, CSV, JSON)',
                              onPressed:
                                  widget.isGenerating ||
                                      widget.isIndexingDocument
                                  ? null
                                  : widget.onAttachFiles,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14.5,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.attachedDocuments.isNotEmpty
                                  ? 'Ask a question about your attached document(s)...'
                                  : (widget.hasModelLoaded
                                        ? 'Message Sovereign AI...'
                                        : 'Message (Inference engine offline)...'),
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 14.5,
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: IconButton.filled(
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: widget.isGenerating
                                    ? theme.colorScheme.error
                                    : (_hasText
                                          ? theme.colorScheme.primary
                                          : (isDark
                                                ? const Color(0xFF3F3F46)
                                                : const Color(0xFFE4E4E7))),
                                foregroundColor: widget.isGenerating
                                    ? Colors.white
                                    : (_hasText
                                          ? Colors.white
                                          : (isDark
                                                ? const Color(0xFFA1A1AA)
                                                : const Color(0xFF71717A))),
                                elevation: 0,
                              ),
                              onPressed: widget.isGenerating
                                  ? widget.onStop
                                  : (_hasText ? _handleSend : null),
                              tooltip: widget.isGenerating
                                  ? 'Stop generation'
                                  : (_hasText
                                        ? 'Send message'
                                        : 'Type to send'),
                              icon: widget.isGenerating
                                  ? const Icon(Icons.stop_rounded, size: 18)
                                  : const Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
