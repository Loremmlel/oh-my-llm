import '../domain/models/chat_message.dart';
import '../../settings/domain/models/llm_model_config.dart';

abstract class ChatCompletionClient {
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  });
}

class ChatCompletionChunk {
  const ChatCompletionChunk({this.contentDelta = '', this.reasoningDelta = ''});

  final String contentDelta;
  final String reasoningDelta;

  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

class ChatCompletionRequestMessage {
  const ChatCompletionRequestMessage({
    required this.role,
    required this.content,
  });

  final ChatMessageRole role;
  final String content;

  Map<String, dynamic> toJson() {
    return {'role': role.apiValue, 'content': content};
  }
}
