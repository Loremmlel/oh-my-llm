import '../domain/models/chat_message.dart';
import '../../settings/domain/models/llm_model_config.dart';

/// 流式补全请求失败时抛出的业务异常。
class ChatCompletionException implements Exception {
  const ChatCompletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 聊天补全客户端抽象。
abstract class ChatCompletionClient {
  /// 以流式方式拉取模型回复增量。
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  });

  /// 以一次性方式获取完整回复。
  Future<ChatCompletionResult> complete({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    await for (final chunk in streamCompletion(
      modelConfig: modelConfig,
      messages: messages,
      reasoningEffort: reasoningEffort,
    )) {
      contentBuffer.write(chunk.contentDelta);
      reasoningBuffer.write(chunk.reasoningDelta);
    }
    return ChatCompletionResult(
      content: contentBuffer.toString(),
      reasoningContent: reasoningBuffer.toString(),
    );
  }
}

/// 流式返回的一段补全增量。
class ChatCompletionChunk {
  const ChatCompletionChunk({this.contentDelta = '', this.reasoningDelta = ''});

  final String contentDelta;
  final String reasoningDelta;

  /// 当内容增量和推理增量都为空时，说明这段 chunk 没有有效内容。
  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

/// 一次性请求返回的完整结果。
class ChatCompletionResult {
  const ChatCompletionResult({this.content = '', this.reasoningContent = ''});

  final String content;
  final String reasoningContent;
}

/// 发给模型 API 的单条请求消息。
class ChatCompletionRequestMessage {
  const ChatCompletionRequestMessage({
    required this.role,
    required this.content,
  });

  final ChatMessageRole role;
  final String content;

  /// 转换为 API 所需的 JSON 结构。
  Map<String, dynamic> toJson() {
    return {'role': role.apiValue, 'content': content};
  }
}
