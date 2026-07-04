import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

import '../chat_message_parent.dart';
import 'chat_checkpoint.dart';
import 'chat_message.dart';

const rootConversationParentId = '__root__';
const noPresetPromptSelectedId = '__no_preset_prompt_selected__';

/// 单个会话及其消息树状态。
class ChatConversation extends Equatable {
  const ChatConversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.messageNodes = const [],
    this.selectedChildByParentId = const {},
    this.checkpoints = const [],
    this.selectedModelId,
    this.selectedCheckpointId,
    this.selectedPresetPromptId,
    this.reasoningEnabled = false,
    this.reasoningEffort = ReasoningEffort.medium,
    this.autoRetryEnabled = false,
    this.excludedMessageIds = const [],
  });

  final String id;
  final String? title;
  final List<ChatMessage> messageNodes;
  final Map<String, String> selectedChildByParentId;
  final List<ChatCheckpoint> checkpoints;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? selectedModelId;
  final String? selectedCheckpointId;
  final String? selectedPresetPromptId;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool autoRetryEnabled;
  final List<String> excludedMessageIds;

  /// 当前会话实际展示的消息序列。
  List<ChatMessage> get messages => _resolveActivePath(
    nodes: messageNodes,
    selectedChildByParentId: selectedChildByParentId,
  );

  /// 会话是否包含任何消息。
  bool get hasMessages => messages.isNotEmpty;

  /// 当前消息是否被排除出后续请求上下文。
  bool isMessageExcluded(String messageId) {
    return excludedMessageIds.contains(messageId);
  }

  /// 是否存在用户手动设置的标题。
  bool get hasCustomTitle => title != null && title!.trim().isNotEmpty;

  /// 优先返回显式标题；否则用首条用户消息截断生成标题。
  String get resolvedTitle {
    if (hasCustomTitle) {
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
    List<ChatMessage>? messageNodes,
    Map<String, String>? selectedChildByParentId,
    List<ChatCheckpoint>? checkpoints,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? selectedModelId,
    String? selectedCheckpointId,
    String? selectedPresetPromptId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool? autoRetryEnabled,
    List<String>? excludedMessageIds,
    bool clearSelectedModelId = false,
    bool clearSelectedCheckpointId = false,
    bool clearSelectedPresetPromptId = false,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messageNodes: messageNodes ?? this.messageNodes,
      selectedChildByParentId:
          selectedChildByParentId ?? this.selectedChildByParentId,
      checkpoints: checkpoints ?? this.checkpoints,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedModelId: clearSelectedModelId
          ? null
          : selectedModelId ?? this.selectedModelId,
      selectedCheckpointId: clearSelectedCheckpointId
          ? null
          : selectedCheckpointId ?? this.selectedCheckpointId,
      selectedPresetPromptId: clearSelectedPresetPromptId
          ? null
          : selectedPresetPromptId ?? this.selectedPresetPromptId,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      autoRetryEnabled: autoRetryEnabled ?? this.autoRetryEnabled,
      excludedMessageIds: excludedMessageIds ?? this.excludedMessageIds,
    );
  }

  /// 将会话序列化为持久化 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messageNodes': messageNodes
          .map((message) => message.toJson())
          .toList(),
      'selectedChildByParentId': selectedChildByParentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedModelId': selectedModelId,
      'selectedCheckpointId': selectedCheckpointId,
      'selectedPresetPromptId': selectedPresetPromptId,
      'checkpoints': checkpoints
          .map((checkpoint) => checkpoint.toJson())
          .toList(),
      'reasoningEnabled': reasoningEnabled,
      'reasoningEffort': reasoningEffort.apiValue,
      'autoRetryEnabled': autoRetryEnabled,
      'excludedMessageIds': excludedMessageIds,
    };
  }

  /// 从持久化 JSON 反序列化会话。
  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final rawMessageNodes = json['messageNodes'] as List<dynamic>? ?? const [];
    final rawSelections =
        json['selectedChildByParentId'] as Map<String, dynamic>? ?? const {};
    final rawCheckpoints = json['checkpoints'] as List<dynamic>? ?? const [];
    final rawExcludedMessageIds =
        json['excludedMessageIds'] as List<dynamic>? ?? const [];

    return ChatConversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      messageNodes: rawMessageNodes
          .map(
            (message) => ChatMessage.fromJson(
              Map<String, dynamic>.from(message as Map),
            ),
          )
          .toList(growable: false),
      selectedChildByParentId:
          rawSelections.map((key, value) => MapEntry(key, value as String)),
      checkpoints: rawCheckpoints
          .map(
            (checkpoint) => ChatCheckpoint.fromJson(
              Map<String, dynamic>.from(checkpoint as Map),
            ),
          )
          .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      selectedModelId: json['selectedModelId'] as String?,
      selectedCheckpointId: json['selectedCheckpointId'] as String?,
      selectedPresetPromptId: json['selectedPresetPromptId'] as String?,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningEffort: ReasoningEffort.values.firstWhere(
        (effort) => effort.apiValue == json['reasoningEffort'],
        orElse: () => ReasoningEffort.medium,
      ),
      autoRetryEnabled: json['autoRetryEnabled'] as bool? ?? false,
      excludedMessageIds: rawExcludedMessageIds
          .whereType<String>()
          .toSet()
          .toList(growable: false),
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
      final parentId = node.effectiveParentId;
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

  @override
  List<Object?> get props => [
    id,
    title,
    messageNodes,
    selectedChildByParentId.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .toList(growable: false),
    checkpoints,
    createdAt,
    updatedAt,
    selectedModelId,
    selectedCheckpointId,
    selectedPresetPromptId,
    reasoningEnabled,
    reasoningEffort,
    autoRetryEnabled,
    excludedMessageIds,
  ];
}
