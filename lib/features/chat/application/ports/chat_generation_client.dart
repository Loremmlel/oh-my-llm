import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import '../../domain/models/chat_message.dart';

/// 流式生成请求失败时抛出的业务异常。
///
/// 面向开发者：尽量携带原始诊断信息（请求目标、HTTP 状态码、厂商错误码、
/// 响应体、源异常与堆栈），由上层格式化为可复制的错误详情，
/// 而非「傻瓜友好」文案。
class ChatGenerationException implements Exception {
  const ChatGenerationException(
    this.message, {
    this.protocol,
    this.uri,
    this.statusCode,
    this.apiErrorCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });

  final String message;

  /// 请求目标协议（发生时可识别时填充）。
  final LlmApiProtocol? protocol;

  /// 请求目标 URI（URL 解析成功后可识别时填充）。
  final Uri? uri;

  /// HTTP 状态码（非 2xx 响应时可用）。
  final int? statusCode;

  /// 厂商错误码（从官方错误 envelope 提取）。
  final String? apiErrorCode;

  /// 原始响应体（HTTP 错误或 SSE 解析失败时的原文）。
  final String? responseBody;

  /// 被包装的源异常（连接中断、TLS 握手失败等）。
  final Object? cause;

  /// 源异常对应的堆栈。
  final StackTrace? causeStackTrace;

  @override
  String toString() => message;
}

/// 一次生成的请求目标（协议中立）。
///
/// 过渡阶段由 [ChatGenerationRequestTarget.fromModelConfig] 从模型配置派生；
/// 接入 LlmEndpointResolver 后，调用方改传解析后的 endpoint。
class ChatGenerationRequestTarget extends Equatable {
  const ChatGenerationRequestTarget({
    required this.protocol,
    required this.endpoint,
    required this.apiKey,
    required this.model,
  });

  /// 从模型配置派生请求目标（过渡约定，字段直接取配置原始值）。
  factory ChatGenerationRequestTarget.fromModelConfig(
    LlmModelConfig modelConfig,
  ) {
    return ChatGenerationRequestTarget(
      protocol: modelConfig.apiProtocol,
      endpoint: modelConfig.apiUrl,
      apiKey: modelConfig.apiKey,
      model: modelConfig.modelName,
    );
  }

  final LlmApiProtocol protocol;

  /// 生成接口端点（本阶段为配置中的原始 apiUrl，不做 URL 解析）。
  final String endpoint;

  final String apiKey;

  /// 模型名（服务商侧模型标识）。
  final String model;

  @override
  List<Object?> get props => [protocol, endpoint, apiKey, model];
}

/// 协议中立的生成请求。
///
/// 消息已由消息构建器完成 5 步拼接（检查点记忆 -> before 模板 -> 对话过滤 ->
/// beforeLatestInput 模板 -> after 模板），client 只按 [target] 路由与编码，
/// 不再感知会话级上下文。
class ChatGenerationRequest extends Equatable {
  const ChatGenerationRequest({
    required this.target,
    required this.messages,
    this.reasoningEffort,
    this.streamIdleTimeout,
  });

  final ChatGenerationRequestTarget target;

  final List<ChatRequestMessage> messages;

  final ReasoningEffort? reasoningEffort;

  /// SSE 空闲超时；null 表示不启用。
  final Duration? streamIdleTimeout;

  @override
  List<Object?> get props => [
    target,
    messages,
    reasoningEffort,
    streamIdleTimeout,
  ];
}

/// 聊天生成客户端抽象。
abstract class ChatGenerationClient {
  /// 以流式方式拉取模型回复增量。
  ///
  /// [ChatGenerationRequest.streamIdleTimeout] 非空时，若 SSE 流在该时长内
  /// 没有任何新数据，则抛出 [ChatGenerationException] 并关闭流。
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request);

  /// 以一次性方式获取完整回复（由基类折叠 [streamCompletion] 得到）。
  Future<ChatGenerationResult> complete(ChatGenerationRequest request) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    String? finishReason;
    await for (final chunk in streamCompletion(request)) {
      contentBuffer.write(chunk.contentDelta);
      reasoningBuffer.write(chunk.reasoningDelta);
      if (chunk.finishReason != null) {
        finishReason = chunk.finishReason;
      }
    }
    return ChatGenerationResult(
      content: contentBuffer.toString(),
      reasoningContent: reasoningBuffer.toString(),
      finishReason: finishReason,
    );
  }
}

/// 流式返回的一段补全增量。
class ChatGenerationChunk {
  const ChatGenerationChunk({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.finishReason,
    this.usage,
  });

  final String contentDelta;
  final String reasoningDelta;

  /// 模型返回的停止原因（如 "stop"、"length"），仅最后一个 chunk 非空。
  final String? finishReason;

  /// 厂商响应自然携带的用量统计，仅流尾部非 null；协议未提供时保持 null。
  final ChatGenerationUsage? usage;

  /// 当内容增量和推理增量都为空时，说明这段 chunk 没有有效内容。
  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

/// 一次请求的 token 用量（厂商提供时才非 null）。
///
/// 协议没有提供某项时保持 null，不以 0 伪装为已知值；本次不新增 usage
/// 持久化或 UI。
class ChatGenerationUsage extends Equatable {
  const ChatGenerationUsage({
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;

  @override
  List<Object?> get props => [
    inputTokens,
    outputTokens,
    reasoningTokens,
    cachedInputTokens,
  ];
}

/// 一次性请求返回的完整结果。
class ChatGenerationResult {
  const ChatGenerationResult({
    this.content = '',
    this.reasoningContent = '',
    this.finishReason,
  });

  final String content;
  final String reasoningContent;

  /// 模型返回的停止原因（如 "stop"、"length"）。
  final String? finishReason;
}

/// 发给模型 API 的单条请求消息。
class ChatRequestMessage {
  const ChatRequestMessage({required this.role, required this.content});

  final ChatMessageRole role;
  final String content;

  /// 转换为 API 所需的 JSON 结构。
  Map<String, dynamic> toJson() {
    return {'role': role.apiValue, 'content': content};
  }
}

/// 必须由 app composition 或测试显式绑定的聊天生成客户端。
final chatGenerationClientProvider = Provider<ChatGenerationClient>((ref) {
  throw StateError('ChatGenerationClient 尚未由应用组合层绑定');
});
