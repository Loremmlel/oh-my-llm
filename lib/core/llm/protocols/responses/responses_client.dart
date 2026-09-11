import 'dart:convert';

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import '../llm_input_encoder.dart';
import '../llm_response_accumulator.dart';
import 'responses_parser.dart';

/// 官方 OpenAI Responses 协议客户端。
///
/// 请求目标携带原始 API URL，本客户端在发送前解析最终生成端点，并负责协议
/// 编码与解析：固定请求头与请求体形状，经共享
/// [LlmHttpStreamTransport] 发送与解码 SSE，再由 [ResponsesParser] 转换为
/// 协议中立增量。客户端无状态：始终不发送 `previous_response_id` 或
/// `conversation`，服务端续接字段全部省略。
class ResponsesClient extends LlmClient {
  ResponsesClient({required this._transport});

  final LlmHttpStreamTransport _transport;

  static const _baseHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  };

  /// 空响应诊断缓冲的原始 SSE 行数上限：只保留尾部，防止超长流撑爆内存。
  static const _maxRawSseLines = 200;

  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) async* {
    if (request.target.protocol != LlmApiProtocol.responses) {
      throw LlmException(
        '协议不匹配：Responses 客户端只能处理 responses 协议请求',
        protocol: request.target.protocol,
      );
    }

    final uri = _resolveEndpoint(request);
    final startedAt = DateTime.now();
    final reasoning = <String, Object>{
      if (request.options.reasoningEffort case final effort?)
        'effort': effort.apiValue,
      if (request.options.protocolOptions case ResponsesOptions(
        reasoningSummary: ResponsesReasoningSummary.auto,
      ))
        'summary': 'auto',
      if (request.options.protocolOptions case ResponsesOptions(
        reasoningContext: ResponsesReasoningContext.currentTurn,
      ))
        'context': 'current_turn',
    };
    final payload = <String, Object>{
      'model': request.target.model,
      'stream': true,
      // 客户端无状态模式：不落服务端存储，也不发送续接字段。
      'store': false,
      ...encodeLlmInput(request, uri),
      ...encodeLlmTools(request),
      ...encodeLlmOptions(request),
      if (request.hasNativeContext) 'include': ['reasoning.encrypted_content'],
      if (reasoning.isNotEmpty) 'reasoning': reasoning,
    };

    // 每次请求独立的 parser：事件间无状态，不跨请求复用。
    final parser = ResponsesParser(protocol: request.target.protocol, uri: uri);

    final rawSseData = <String>[];
    final accumulated = LlmResponseAccumulator();

    try {
      await for (final event in _transport.streamEvents(
        uri: uri,
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${request.target.apiKey}',
        },
        body: jsonEncode(payload),
        idleTimeout: request.options.streamIdleTimeout,
        responseHeaderTimeout: request.options.responseHeaderTimeout,
        control: control,
        requestId: control.requestId,
        attempt: 1,
        logRawResponse: !request.hasNativeContext,
      )) {
        if (!request.hasNativeContext) rawSseData.add(event.rawData);
        // 诊断缓冲只保留尾部，超出的行直接丢弃。
        if (rawSseData.length > _maxRawSseLines) {
          rawSseData.removeRange(0, rawSseData.length - _maxRawSseLines);
        }
        final parsed = parser.parse(event);
        yield* Stream.fromIterable(parser.takeToolDeltas());
        if (!parsed.recognized) {
          // 未知且与文本无关的事件：记录诊断后忽略（生命周期/记账事件）。
          continue;
        }
        final chunk = parsed.chunk;
        if (chunk != null) {
          accumulated.add(chunk);
          yield chunk;
        }
        if (parsed.isDone) {
          // completed / incomplete：协议终态，立即停止消费底层连接。
          break;
        }
      }
    } on LlmHttpTransportException catch (error) {
      // 传输层异常统一转换为业务异常，保留协议/URI/状态码与原始 cause。
      throw LlmException(
        error.message,
        kind: error.kind,
        protocol: request.target.protocol,
        uri: uri,
        statusCode: error.statusCode,
        responseBody: error.responseBody,
        cause: error.cause,
        causeStackTrace: error.causeStackTrace,
      );
    }
    final calls = parser.finishToolCalls();
    final result = accumulated.finish(
      diagnosticBody: request.hasNativeContext || rawSseData.isEmpty
          ? null
          : rawSseData.join('\n'),
      requestId: control.requestId,
      request: request,
      endpoint: uri,
      nativeItems: parser.hasReliableReplay ? parser.nativeItems : null,
      completedText: parser.completedText,
      toolCalls: calls,
      stopKind: calls.isNotEmpty
          ? LlmStopKind.toolCalls
          : parser.refused
          ? LlmStopKind.refused
          : parser.completed
          ? LlmStopKind.completed
          : parser.rawFinishReason != null
          ? LlmStopKind.incomplete
          : LlmStopKind.unknown,
      rawFinishReason: parser.rawFinishReason,
    );
    _transport.recordCompletion(
      requestId: control.requestId,
      protocol: request.target.protocol.name,
      model: request.target.model,
      stopKind: result.stopKind.name,
      toolCallCount: result.toolCalls.length,
      elapsed: DateTime.now().difference(startedAt),
      usage: result.usage,
    );
    yield LlmCompleted(result);
  }

  /// 在真正发送 HTTP 前把原始服务商 URL 解析为 Responses 端点。
  Uri _resolveEndpoint(LlmRequest request) {
    try {
      return const LlmEndpointResolver().resolveGenerationEndpoint(
        rawUrl: request.target.endpoint,
        protocol: LlmApiProtocol.responses,
      );
    } on LlmEndpointResolverException catch (error, stack) {
      throw LlmException(
        error.message,
        kind: LlmFailureKind.invalidRequest,
        protocol: request.target.protocol,
        cause: error,
        causeStackTrace: stack,
      );
    }
  }
}
