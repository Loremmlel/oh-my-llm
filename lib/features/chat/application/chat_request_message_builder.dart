import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_message.dart';

/// 把提示词模板与会话消息拼装成模型请求消息列表。
List<ChatCompletionRequestMessage> buildRequestMessages({
  required PromptTemplate? promptTemplate,
  required List<ChatMessage> conversationMessages,
  List<ChatCheckpoint> checkpointChain = const [],
}) {
  final requestMessages = <ChatCompletionRequestMessage>[];

  if (promptTemplate != null && promptTemplate.systemPrompt.trim().isNotEmpty) {
    requestMessages.add(
      ChatCompletionRequestMessage(
        role: ChatMessageRole.system,
        content: promptTemplate.systemPrompt.trim(),
      ),
    );
  }

  if (checkpointChain.isNotEmpty) {
    final checkpointBuffer = StringBuffer(
      '当前对话已启用记忆检查点。以下记忆按时间顺序提供，后面的检查点依赖前面的祖先检查点。'
      '请将它们视为用户已确认的重要长期记忆；若与后续原始消息冲突，以后续原始消息为准。',
    );
    for (final checkpoint in checkpointChain) {
      checkpointBuffer
        ..write('\n\n【${checkpoint.title}】\n')
        ..write(checkpoint.content.trim());
    }
    requestMessages.add(
      ChatCompletionRequestMessage(
        role: ChatMessageRole.system,
        content: checkpointBuffer.toString().trim(),
      ),
    );
  }

  if (promptTemplate != null) {
    final beforeMessages = promptTemplate.messages.where(
      (message) => message.placement == PromptMessagePlacement.before,
    );
    requestMessages.addAll(
      beforeMessages.map((message) {
        return ChatCompletionRequestMessage(
          role: message.role == PromptMessageRole.user
              ? ChatMessageRole.user
              : ChatMessageRole.assistant,
          content: message.content,
        );
      }),
    );
  }

  requestMessages.addAll(
    conversationMessages.map((message) {
      return ChatCompletionRequestMessage(
        role: message.role,
        content: message.content,
      );
    }),
  );

  if (promptTemplate != null) {
    final afterMessages = promptTemplate.messages.where(
      (message) => message.placement == PromptMessagePlacement.after,
    );
    requestMessages.addAll(
      afterMessages.map((message) {
        return ChatCompletionRequestMessage(
          role: message.role == PromptMessageRole.user
              ? ChatMessageRole.user
              : ChatMessageRole.assistant,
          content: message.content,
        );
      }),
    );
  }

  return List.unmodifiable(requestMessages);
}
