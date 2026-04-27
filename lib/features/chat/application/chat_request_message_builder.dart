import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_message.dart';

/// 把提示词模板与会话消息拼装成模型请求消息列表。
List<ChatCompletionRequestMessage> buildRequestMessages({
  required PromptTemplate? promptTemplate,
  required List<ChatMessage> conversationMessages,
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

  if (promptTemplate != null) {
    // 模板消息始终排在会话消息前面，保持与后端请求顺序一致。
    requestMessages.addAll(
      promptTemplate.messages.map((message) {
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

  return List.unmodifiable(requestMessages);
}
