import 'dart:convert';

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';

import '../../application/ports/chat_generation_client.dart';
import 'chat_completions_parser.dart';

/// 官方 Chat Completions 协议客户端。
///
/// 请求目标携带原始 API URL，本客户端在发送前解析最终生成端点，并负责协议
/// 编码与解析：固定请求头与请求体形状，经共享
/// [LlmHttpStreamTransport] 发送与解码 SSE，再由 [ChatCompletionsParser]
/// 转换为协议中立增量。不包含任何厂商 host 匹配或请求补丁。
class ChatCompletionsClient extends ChatGenerationClient {
  ChatCompletionsClient({required LlmHttpStreamTransport transport})
    : _transport = transport;

  final LlmHttpStreamTransport _transport;

  static const _baseHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  };

  /// 空响应诊断缓冲的原始 SSE 行数上限：只保留尾部，防止超长流撑爆内存。
  static const _maxRawSseLines = 200;

  @override
  Stream<ChatGenerationChunk> streamCompletion(
    ChatGenerationRequest request,
  ) async* {
    if (request.target.protocol != LlmApiProtocol.chatCompletions) {
      throw ChatGenerationException(
        '协议不匹配：ChatCompletions 客户端只能处理 chatCompletions 协议请求',
        protocol: request.target.protocol,
      );
    }

    final uri = _resolveEndpoint(request);
    final payload = <String, Object>{
      'model': request.target.model,
      'stream': true,
      'messages': [
        for (final message in request.messages)
          {'role': message.role.apiValue, 'content': message.content},
      ],
      // 只在模型支持 reasoning 且当前会话启用时发送，其余情况省略。
      if (request.reasoningEffort case final effort?)
        'reasoning_effort': effort.apiValue,
    };

    // 每次请求独立的 parser：splitter 的跨 chunk 状态不跨请求复用。
    final parser = ChatCompletionsParser(
      protocol: request.target.protocol,
      uri: uri,
    );

    final rawSseData = <String>[];
    var hadContent = false;

    try {
      await for (final event in _transport.streamEvents(
        uri: uri,
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${request.target.apiKey}',
        },
        body: jsonEncode(payload),
        idleTimeout: request.streamIdleTimeout,
      )) {
        rawSseData.add(event.rawData);
        // 诊断缓冲只保留尾部，超出的行直接丢弃。
        if (rawSseData.length > _maxRawSseLines) {
          rawSseData.removeRange(0, rawSseData.length - _maxRawSseLines);
        }
        final parsed = parser.parse(event);
        final chunk = parsed.chunk;
        if (chunk != null) {
          if (!chunk.isEmpty) {
            hadContent = true;
          }
          yield chunk;
        }
        if (parsed.isDone) {
          // [DONE]：正常流结束，停止消费。
          break;
        }
      }
    } on LlmHttpTransportException catch (error) {
      // 传输层异常统一转换为业务异常，保留协议/URI/状态码与原始 cause。
      throw ChatGenerationException(
        error.message,
        protocol: request.target.protocol,
        uri: uri,
        statusCode: error.statusCode,
        responseBody: error.responseBody,
        cause: error.cause,
        causeStackTrace: error.causeStackTrace,
      );
    }

    // 流末尾的不完整标签文本按当前通道刷新。
    final trailing = parser.finish();
    if (trailing != null && !trailing.isEmpty) {
      hadContent = true;
      yield trailing;
    }

    if (!hadContent) {
      throw ChatGenerationException(
        '请求未返回有效内容',
        protocol: request.target.protocol,
        uri: uri,
        responseBody: rawSseData.isEmpty ? null : rawSseData.join('\n'),
      );
    }
  }

  /// 在真正发送 HTTP 前把原始服务商 URL 解析为 Chat Completions 端点。
  Uri _resolveEndpoint(ChatGenerationRequest request) {
    try {
      return const LlmEndpointResolver().resolveGenerationEndpoint(
        rawUrl: request.target.endpoint,
        protocol: LlmApiProtocol.chatCompletions,
      );
    } on LlmEndpointResolverException catch (error, stack) {
      throw ChatGenerationException(
        error.message,
        protocol: request.target.protocol,
        cause: error,
        causeStackTrace: stack,
      );
    }
  }
}
