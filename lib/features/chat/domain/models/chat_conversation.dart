import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

import 'chat_message.dart';

const rootConversationParentId = '__root__';

/// 单个会话及其消息树状态。
class ChatConversation extends Equatable {
  const ChatConversation({
    required this.id,
    required List<ChatMessage> messages,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.messageNodes = const [],
    this.selectedChildByParentId = const {},
    this.selectedModelId,
    this.selectedPromptTemplateId,
    this.reasoningEnabled = false,
    this.reasoningEffort = ReasoningEffort.medium,
  }) : _messages = messages;

  final String id;
  final String? title;
  final List<ChatMessage> _messages;
  final List<ChatMessage> messageNodes;
  final Map<String, String> selectedChildByParentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? selectedModelId;
  final String? selectedPromptTemplateId;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  /// 当前会话实际展示的消息序列。
  List<ChatMessage> get messages {
    if (messageNodes.isEmpty) {
      return _messages;
    }

    final resolvedPath = _resolveActivePath(
      nodes: messageNodes,
      selectedChildByParentId: selectedChildByParentId,
    );
    return resolvedPath.isEmpty ? _messages : resolvedPath;
  }

  /// 会话是否包含任何消息。
  bool get hasMessages => messages.isNotEmpty;

  /// 优先返回显式标题；否则用首条用户消息截断生成标题。
  String get resolvedTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }

    final firstUserMessage = messages.where((message) {
      return message.role == ChatMessageRole.user;
    }).firstOrNull;

    if (firstUserMessage == null || firstUserMessage.content.trim().isEmpty) {
      return '未命名对话';
    }

    final normalizedContent = firstUserMessage.content.trim();
    return normalizedContent.characters.take(15).toString();
  }

  /// 复制当前会话，并允许单独覆盖或清空部分字段。
  ChatConversation copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    List<ChatMessage>? messageNodes,
    Map<String, String>? selectedChildByParentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? selectedModelId,
    String? selectedPromptTemplateId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool clearSelectedModelId = false,
    bool clearSelectedPromptTemplateId = false,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      messageNodes: messageNodes ?? this.messageNodes,
      selectedChildByParentId:
          selectedChildByParentId ?? this.selectedChildByParentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedModelId: clearSelectedModelId
          ? null
          : selectedModelId ?? this.selectedModelId,
      selectedPromptTemplateId: clearSelectedPromptTemplateId
          ? null
          : selectedPromptTemplateId ?? this.selectedPromptTemplateId,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }

  /// 将会话序列化为持久化 JSON。
  Map<String, dynamic> toJson() {
    final effectiveNodes = messageNodes.isEmpty
        ? _buildLinearMessageNodes(_messages)
        : messageNodes;
    final effectiveSelections = messageNodes.isEmpty
        ? _buildLinearSelections(effectiveNodes)
        : selectedChildByParentId;

    return {
      'id': id,
      'title': title,
      'messages': messages.map((message) => message.toJson()).toList(),
      'messageNodes': effectiveNodes
          .map((message) => message.toJson())
          .toList(),
      'selectedChildByParentId': effectiveSelections,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedModelId': selectedModelId,
      'selectedPromptTemplateId': selectedPromptTemplateId,
      'reasoningEnabled': reasoningEnabled,
      'reasoningEffort': reasoningEffort.apiValue,
    };
  }

  /// 从持久化 JSON 反序列化会话。
  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    final rawMessageNodes = json['messageNodes'] as List<dynamic>? ?? const [];
    final rawSelections =
        json['selectedChildByParentId'] as Map<String, dynamic>? ?? const {};
    final parsedMessages = rawMessages
        .map((message) {
          return ChatMessage.fromJson(
            Map<String, dynamic>.from(message as Map),
          );
        })
        .toList(growable: false);
    final parsedMessageNodes = rawMessageNodes
        .map((message) {
          return ChatMessage.fromJson(
            Map<String, dynamic>.from(message as Map),
          );
        })
        .toList(growable: false);

    final hasTreeData = parsedMessageNodes.isNotEmpty;
    final effectiveNodes = hasTreeData
        ? parsedMessageNodes
        : _buildLinearMessageNodes(parsedMessages);
    final effectiveSelections = hasTreeData
        ? rawSelections.map((key, value) => MapEntry(key, value as String))
        : _buildLinearSelections(effectiveNodes);

    return ChatConversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      messages: parsedMessages,
      messageNodes: effectiveNodes,
      selectedChildByParentId: effectiveSelections,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      selectedModelId: json['selectedModelId'] as String?,
      selectedPromptTemplateId: json['selectedPromptTemplateId'] as String?,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningEffort: ReasoningEffort.values.firstWhere(
        (effort) => effort.apiValue == json['reasoningEffort'],
        orElse: () => ReasoningEffort.medium,
      ),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  /// 解析当前会话中按选择路径生效的消息链。
  static List<ChatMessage> _resolveActivePath({
    required List<ChatMessage> nodes,
    required Map<String, String> selectedChildByParentId,
  }) {
    if (nodes.isEmpty) {
      return const [];
    }

    final childrenByParent = <String, List<ChatMessage>>{};
    for (final node in nodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      childrenByParent.putIfAbsent(parentId, () => <ChatMessage>[]).add(node);
    }

    final path = <ChatMessage>[];
    var parentId = rootConversationParentId;
    while (true) {
      final siblings = childrenByParent[parentId];
      if (siblings == null || siblings.isEmpty) {
        break;
      }

      final selectedChildId = selectedChildByParentId[parentId];
      final selectedNode =
          siblings.where((node) => node.id == selectedChildId).firstOrNull ??
          siblings.first;
      path.add(selectedNode);
      parentId = selectedNode.id;
    }

    return List.unmodifiable(path);
  }

  /// 把线性消息序列补成单链消息树。
  static List<ChatMessage> _buildLinearMessageNodes(
    List<ChatMessage> messages,
  ) {
    if (messages.isEmpty) {
      return const [];
    }

    String parentId = rootConversationParentId;
    final nodes = messages
        .map((message) {
          final next = message.copyWith(parentId: parentId);
          parentId = next.id;
          return next;
        })
        .toList(growable: false);
    return List.unmodifiable(nodes);
  }

  /// 为线性消息树生成默认选择映射。
  static Map<String, String> _buildLinearSelections(List<ChatMessage> nodes) {
    if (nodes.isEmpty) {
      return const {};
    }

    final selections = <String, String>{};
    for (final node in nodes) {
      final parentId = node.parentId ?? rootConversationParentId;
      selections[parentId] = node.id;
    }
    return Map.unmodifiable(selections);
  }

  @override
  List<Object?> get props => [
    id,
    title,
    _messages,
    messageNodes,
    selectedChildByParentId.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .toList(growable: false),
    createdAt,
    updatedAt,
    selectedModelId,
    selectedPromptTemplateId,
    reasoningEnabled,
    reasoningEffort,
  ];
}
