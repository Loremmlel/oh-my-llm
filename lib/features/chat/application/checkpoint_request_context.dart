import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_message.dart';
import '../../settings/domain/models/memory_prompt.dart';

/// 选中检查点后，真正参与请求拼装的上下文视图。
class CheckpointRequestContext {
  const CheckpointRequestContext({
    this.checkpointChain = const [],
    this.tailMessages = const [],
  });

  final List<ChatCheckpoint> checkpointChain;
  final List<ChatMessage> tailMessages;

  bool get hasCheckpoint => checkpointChain.isNotEmpty;
  ChatCheckpoint? get activeCheckpoint => checkpointChain.lastOrNull;
}

/// 解析当前请求可用的检查点链与其后的增量消息。
CheckpointRequestContext resolveCheckpointRequestContext({
  required List<ChatCheckpoint> checkpoints,
  required String? selectedCheckpointId,
  required List<ChatMessage> conversationMessages,
}) {
  if (selectedCheckpointId == null) {
    return CheckpointRequestContext(
      tailMessages: List.unmodifiable(conversationMessages),
    );
  }

  final checkpointChain = resolveCheckpointChain(
    checkpoints: checkpoints,
    selectedCheckpointId: selectedCheckpointId,
  );
  if (checkpointChain.isEmpty) {
    return CheckpointRequestContext(
      tailMessages: List.unmodifiable(conversationMessages),
    );
  }

  final coveredUntilMessageId = checkpointChain.last.coveredUntilMessageId;
  if (coveredUntilMessageId == null) {
    return CheckpointRequestContext(
      checkpointChain: List.unmodifiable(checkpointChain),
      tailMessages: List.unmodifiable(conversationMessages),
    );
  }

  final coveredIndex = conversationMessages.indexWhere((message) {
    return message.id == coveredUntilMessageId;
  });
  if (coveredIndex == -1) {
    return CheckpointRequestContext(
      tailMessages: List.unmodifiable(conversationMessages),
    );
  }

  return CheckpointRequestContext(
    checkpointChain: List.unmodifiable(checkpointChain),
    tailMessages: List.unmodifiable(
      conversationMessages.skip(coveredIndex + 1).toList(growable: false),
    ),
  );
}

/// 按祖先顺序解析检查点链。
List<ChatCheckpoint> resolveCheckpointChain({
  required List<ChatCheckpoint> checkpoints,
  required String? selectedCheckpointId,
}) {
  if (selectedCheckpointId == null) {
    return const [];
  }

  final checkpointsById = <String, ChatCheckpoint>{
    for (final checkpoint in checkpoints) checkpoint.id: checkpoint,
  };
  final chain = <ChatCheckpoint>[];
  final visitedIds = <String>{};
  String? currentId = selectedCheckpointId;
  while (currentId != null) {
    if (!visitedIds.add(currentId)) {
      break;
    }
    final checkpoint = checkpointsById[currentId];
    if (checkpoint == null) {
      break;
    }
    chain.add(checkpoint);
    currentId = checkpoint.parentCheckpointId;
  }
  return chain.reversed.toList(growable: false);
}

/// 构建用于普通聊天请求的检查点系统消息。
List<ChatCompletionRequestMessage> buildCheckpointMemoryMessages(
  List<ChatCheckpoint> checkpointChain,
) {
  if (checkpointChain.isEmpty) {
    return const [];
  }

  final buffer = StringBuffer(
    '当前对话已启用记忆检查点。以下内容按时间顺序提供，后面的检查点依赖前面的祖先检查点。'
    '请将它们视为用户已确认的重要长期记忆；若与后续原始消息冲突，以后续原始消息为准。',
  );
  for (final checkpoint in checkpointChain) {
    buffer
      ..write('\n\n【${checkpoint.title}】\n')
      ..write(checkpoint.content.trim());
  }

  return [
    ChatCompletionRequestMessage(
      role: ChatMessageRole.system,
      content: buffer.toString().trim(),
    ),
  ];
}

/// 构建创建新检查点时的总结请求。
List<ChatCompletionRequestMessage> buildCheckpointSummaryMessages({
  required MemoryPrompt memoryPrompt,
  required List<ChatMessage> conversationMessages,
  List<ChatCheckpoint> checkpointChain = const [],
}) {
  final requestMessages = <ChatCompletionRequestMessage>[
    ChatCompletionRequestMessage(
      role: ChatMessageRole.system,
      content: checkpointChain.isEmpty
          ? '你正在为当前对话创建根检查点。请提炼可长期复用的重要事实、约束、决定、待办和上下文。输出应简洁、结构清晰，并适合后续继续对话时直接作为记忆使用。'
          : '你正在为当前对话创建新的链式检查点。已有检查点会与本次新检查点一起在后续对话中使用。除非为了消除歧义必须重述，否则不要机械重复旧检查点，重点总结自最后一个已提供检查点之后新增或变化的重要信息。',
    ),
  ];

  requestMessages.addAll(buildCheckpointMemoryMessages(checkpointChain));
  requestMessages.addAll(
    conversationMessages.map((message) {
      return ChatCompletionRequestMessage(
        role: message.role,
        content: message.content,
      );
    }),
  );
  requestMessages.add(
    ChatCompletionRequestMessage(
      role: ChatMessageRole.user,
      content: '请按照以下记忆总结提示词生成新的检查点：\n\n${memoryPrompt.content.trim()}',
    ),
  );
  return List.unmodifiable(requestMessages);
}
