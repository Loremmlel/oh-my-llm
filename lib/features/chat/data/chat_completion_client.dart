import '../domain/models/chat_message.dart';
import '../../settings/domain/models/llm_model_config.dart';

/// 流式补全请求失败时抛出的业务异常。
///
/// 面向开发者：尽量携带原始诊断信息（HTTP 状态码、响应体、源异常与堆栈），
/// 由上层格式化为可复制的错误详情，而非「傻瓜友好」文案。
class ChatCompletionException implements Exception {
  const ChatCompletionException(
    this.message, {
    this.statusCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });

  final String message;

  /// HTTP 状态码（非 2xx 响应时可用）。
  final int? statusCode;

  /// 原始响应体（HTTP 错误或 SSE 解析失败时的原文）。
  final String? responseBody;

  /// 被包装的源异常（连接中断、TLS 握手失败等）。
  final Object? cause;

  /// 源异常对应的堆栈。
  final StackTrace? causeStackTrace;

  @override
  String toString() => message;
}

/// 聊天补全客户端抽象。
abstract class ChatCompletionClient {
  /// 以流式方式拉取模型回复增量。
  ///
  /// [streamIdleTimeout] 非空时，若 SSE 流在该时长内没有任何新数据，
  /// 则抛出 [ChatCompletionException] 并关闭流。
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
    Duration? streamIdleTimeout,
  });

  /// 以一次性方式获取完整回复。
  Future<ChatCompletionResult> complete({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    String? finishReason;
    await for (final chunk in streamCompletion(
      modelConfig: modelConfig,
      messages: messages,
      reasoningEffort: reasoningEffort,
    )) {
      contentBuffer.write(chunk.contentDelta);
      reasoningBuffer.write(chunk.reasoningDelta);
      if (chunk.finishReason != null) {
        finishReason = chunk.finishReason;
      }
    }
    return ChatCompletionResult(
      content: contentBuffer.toString(),
      reasoningContent: reasoningBuffer.toString(),
      finishReason: finishReason,
    );
  }
}

/// 流式返回的一段补全增量。
class ChatCompletionChunk {
  const ChatCompletionChunk({this.contentDelta = '', this.reasoningDelta = '', this.finishReason});

  final String contentDelta;
  final String reasoningDelta;

  /// 模型返回的停止原因（如 "stop"、"length"），仅最后一个 chunk 非空。
  final String? finishReason;

  /// 当内容增量和推理增量都为空时，说明这段 chunk 没有有效内容。
  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

/// 一次性请求返回的完整结果。
class ChatCompletionResult {
  const ChatCompletionResult({this.content = '', this.reasoningContent = '', this.finishReason});

  final String content;
  final String reasoningContent;

  /// 模型返回的停止原因（如 "stop"、"length"）。
  final String? finishReason;
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
