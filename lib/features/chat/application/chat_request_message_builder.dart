import '../../settings/domain/models/prompt_template.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_message.dart';

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
