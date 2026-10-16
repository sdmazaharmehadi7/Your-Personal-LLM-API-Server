import 'chat_message.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final String? modelId;
  final String? activeModelName;
  final List<String> attachedDocumentIds;

  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.modelId,
    this.activeModelName,
    this.attachedDocumentIds = const [],
  });

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    String? modelId,
    String? activeModelName,
    List<String>? attachedDocumentIds,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      modelId: modelId ?? this.modelId,
      activeModelName: activeModelName ?? this.activeModelName,
      attachedDocumentIds: attachedDocumentIds ?? this.attachedDocumentIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'modelId': modelId,
    'activeModelName': activeModelName,
    'attachedDocumentIds': attachedDocumentIds,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? [];
    final rawDocIds = json['attachedDocumentIds'] as List<dynamic>? ?? [];
    return ChatSession(
      id:
          json['id'] as String? ??
          'session_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Conversation',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      modelId: json['modelId'] as String?,
      activeModelName: json['activeModelName'] as String?,
      attachedDocumentIds: rawDocIds.map((e) => e.toString()).toList(),
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map((m) => ChatMessage.fromJson(m))
          .toList(),
    );
  }
}
