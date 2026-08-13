import 'dart:convert';

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';

import '../../../application/ports/chat_generation_client.dart';
import 'responses_parser.dart';

/// 官方 OpenAI Responses 协议客户端。
///
/// 请求目标携带原始 API URL，本客户端在发送前解析最终生成端点，并负责协议
/// 编码与解析：固定请求头与请求体形状，经共享
/// [LlmHttpStreamTransport] 发送与解码 SSE，再由 [ResponsesParser] 转换为
/// 协议中立增量。客户端无状态：始终不发送 `previous_response_id` 或
/// `conversation`，服务端续接字段全部省略。
class ResponsesClient extends ChatGenerationClient {
  ResponsesClient({required LlmHttpStreamTransport transport})
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
    if (request.target.protocol != LlmApiProtocol.responses) {
      throw ChatGenerationException(
        '协议不匹配：Responses 客户端只能处理 responses 协议请求',
        protocol: request.target.protocol,
      );
    }

    final uri = _resolveEndpoint(request);
    final payload = <String, Object>{
      'model': request.target.model,
      'stream': true,
      // 客户端无状态模式：不落服务端存储，也不发送续接字段。
      'store': false,
      'input': [
        for (final message in request.messages)
          {'role': message.role.apiValue, 'content': message.content},
      ],
      // 只在模型支持 reasoning 且当前会话启用时发送，其余情况省略。
      if (request.reasoningEffort case final effort?)
        'reasoning': {
          'effort': effort.apiValue,
          'summary': 'auto',
          'context': 'current_turn',
        },
    };

    // 每次请求独立的 parser：事件间无状态，不跨请求复用。
    final parser = ResponsesParser(protocol: request.target.protocol, uri: uri);

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
        if (!parsed.recognized) {
          // 未知且与文本无关的事件：记录诊断后忽略（生命周期/记账事件）。
          continue;
        }
        final chunk = parsed.chunk;
        if (chunk != null) {
          if (!chunk.isEmpty) {
            hadContent = true;
          }
          yield chunk;
        }
        if (parsed.isDone) {
          // completed / incomplete：协议终态，立即停止消费底层连接。
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

    if (!hadContent) {
      throw ChatGenerationException(
        '请求未返回有效内容',
        protocol: request.target.protocol,
        uri: uri,
        responseBody: rawSseData.isEmpty ? null : rawSseData.join('\n'),
      );
    }
  }

  /// 在真正发送 HTTP 前把原始服务商 URL 解析为 Responses 端点。
  Uri _resolveEndpoint(ChatGenerationRequest request) {
    try {
      return const LlmEndpointResolver().resolveGenerationEndpoint(
        rawUrl: request.target.endpoint,
        protocol: LlmApiProtocol.responses,
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
