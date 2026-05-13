import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_message.dart';
import 'request_message_filter.dart';

export 'request_message_filter.dart';

/// 把提示词模板与会话消息拼装成模型请求消息列表。
List<ChatCompletionRequestMessage> buildRequestMessages({
  required PromptTemplate? promptTemplate,
  required List<ChatMessage> conversationMessages,
  List<ChatCheckpoint> checkpointChain = const [],
  RequestMessageFilter filter = RequestMessageFilter.passthrough,
}) {
  final requestMessages = <ChatCompletionRequestMessage>[];
  final filteredMessages = filter.apply(conversationMessages);

  if (checkpointChain.isNotEmpty) {
    requestMessages.addAll(buildCheckpointMemoryMessages(checkpointChain));
  }

  appendTemplateMessages(
    buffer: requestMessages,
    promptTemplate: promptTemplate,
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

  appendTemplateMessages(
    buffer: requestMessages,
    promptTemplate: promptTemplate,
    placement: PromptMessagePlacement.after,
  );

  return List.unmodifiable(requestMessages);
}

/// 构建检查点记忆系统消息，可被多处请求构建函数复用。
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

/// 将 [PromptTemplate] 中指定位置的消息追加到 [buffer]。
void appendTemplateMessages({
  required List<ChatCompletionRequestMessage> buffer,
  required PromptTemplate? promptTemplate,
  required PromptMessagePlacement placement,
}) {
  if (promptTemplate == null) {
    return;
  }
  final messages = promptTemplate.messagesForPlacement(placement);
  buffer.addAll(
    messages.map((message) {
      return ChatCompletionRequestMessage(
        role: switch (message.role) {
          PromptMessageRole.system => ChatMessageRole.system,
          PromptMessageRole.user => ChatMessageRole.user,
          PromptMessageRole.assistant => ChatMessageRole.assistant,
        },
        content: message.content,
      );
    }),
  );
}
