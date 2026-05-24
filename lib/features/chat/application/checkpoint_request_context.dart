import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_message.dart';
import '../../settings/domain/models/memory_prompt.dart';
import '../../settings/domain/models/preset_prompt.dart';
import 'chat_request_message_builder.dart';

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

/// 构建创建新检查点时的总结请求。
List<ChatCompletionRequestMessage> buildCheckpointSummaryMessages({
  required MemoryPrompt memoryPrompt,
  required List<ChatMessage> conversationMessages,
  List<ChatCheckpoint> checkpointChain = const [],
  PresetPrompt? presetPrompt,
  RequestMessageFilter filter = RequestMessageFilter.passthrough,
}) {
  final requestMessages = <ChatCompletionRequestMessage>[];
  final filteredMessages = filter.apply(conversationMessages);

  requestMessages.add(
    ChatCompletionRequestMessage(
      role: ChatMessageRole.system,
      content: checkpointChain.isEmpty
          ? '你正在为当前对话创建根检查点。请提炼可长期复用的重要事实、约束、决定、待办和上下文。输出应简洁、结构清晰，并适合后续继续对话时直接作为记忆使用。'
          : '你正在为当前对话创建新的链式检查点。已有检查点会与本次新检查点一起在后续对话中使用。除非为了消除歧义必须重述，否则不要机械重复旧检查点，重点总结自最后一个已提供检查点之后新增或变化的重要信息。',
    ),
  );

  requestMessages.addAll(buildCheckpointMemoryMessages(checkpointChain));

  appendTemplateMessages(
    buffer: requestMessages,
    presetPrompt: presetPrompt,
    placement: PromptMessagePlacement.before,
  );

  requestMessages.addAll(
    filteredMessages.map((message) {
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

  appendTemplateMessages(
    buffer: requestMessages,
    presetPrompt: presetPrompt,
    placement: PromptMessagePlacement.after,
  );

  return List.unmodifiable(requestMessages);
}
