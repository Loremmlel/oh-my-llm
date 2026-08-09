import 'dart:convert';

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

import '../../application/ports/chat_generation_client.dart';
import '../../domain/models/chat_message.dart';
import 'anthropic_message_transformer.dart';
import 'anthropic_parser.dart';

/// 官方 Anthropic Messages 协议客户端。
///
/// 请求目标由上层解析（[ChatGenerationRequest.target.endpoint] 即最终生成
/// 端点），本客户端只负责协议编码与解析：固定请求头与请求体形状，消息先经
/// [transformAnthropicMessages] 完成 System 转换与同角色合并，再经共享
/// [LlmHttpStreamTransport] 发送与解码 SSE，由 [AnthropicParser] 转换为
/// 协议中立增量。
///
/// 缓存策略：不计算或移动显式缓存断点，只在请求体顶层携带
/// `cache_control`，是否命中由官方自动 Prompt Cache 按稳定请求前缀处理。
/// reasoning：第一阶段只支持 adaptive thinking，不支持手动 budget_tokens；
/// 未启用 reasoning 时省略 `thinking` 与 `output_config`，不按模型名称猜测。
class AnthropicMessagesClient extends ChatGenerationClient {
  AnthropicMessagesClient({required LlmHttpStreamTransport transport})
    : _transport = transport;

  final LlmHttpStreamTransport _transport;

  static const _baseHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  };

  static const _apiVersion = '2023-06-01';

  /// 输出 token 上限：本阶段使用协议内常量，不提供输出长度设置。
  static const _maxTokens = 8192;

  @override
  Stream<ChatGenerationChunk> streamCompletion(
    ChatGenerationRequest request,
  ) async* {
    if (request.target.protocol != LlmApiProtocol.anthropic) {
      throw ChatGenerationException(
        '协议不匹配：Anthropic 客户端只能处理 anthropic 协议请求',
        protocol: request.target.protocol,
      );
    }

    final uri = _parseEndpoint(request);
    final transformed = transformAnthropicMessages(request.messages);
    final payload = <String, Object>{
      'model': request.target.model,
      'stream': true,
      'max_tokens': _maxTokens,
      'cache_control': const {'type': 'ephemeral'},
      // 无 leading System 时省略顶层 system。
      if (transformed.system != null) 'system': transformed.system!,
      'messages': [
        for (final message in transformed.messages)
          {'role': message.role, 'content': message.content},
      ],
      // 只在模型支持 reasoning 且当前会话启用时发送，其余情况省略。
      if (request.reasoningEffort != null)
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
      if (request.reasoningEffort case final effort?)
        'output_config': {'effort': _anthropicEffort(effort)},
    };

    // 每次请求独立的 parser：事件间无状态，不跨请求复用。
    final parser = AnthropicParser(protocol: request.target.protocol, uri: uri);

    final rawSseData = <String>[];
    var hadContent = false;

    try {
      await for (final event in _transport.streamEvents(
        uri: uri,
        headers: {
          ..._baseHeaders,
          'x-api-key': request.target.apiKey,
          'anthropic-version': _apiVersion,
        },
        body: jsonEncode(payload),
        idleTimeout: request.streamIdleTimeout,
      )) {
        rawSseData.add(event.rawData);
        final parsed = parser.parse(event);
        if (!parsed.recognized) {
          // 无法识别的新事件类型：原始 data 已进入缓冲日志（脱敏诊断）。
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
          // message_stop：正常流结束，停止消费。
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

  /// 应用层 reasoning effort 到 Anthropic 值的映射。
  ///
  /// xhigh 与 max 同为 max（协议侧最高档），low/medium/high 原样透传。
  static String _anthropicEffort(ReasoningEffort effort) {
    return switch (effort) {
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high => 'high',
      ReasoningEffort.xhigh || ReasoningEffort.max => 'max',
    };
  }

  /// 解析请求端点并做基础校验；不做生成后缀的 URL 解析（上层已完成）。
  Uri _parseEndpoint(ChatGenerationRequest request) {
    final endpoint = request.target.endpoint;
    try {
      final uri = Uri.parse(endpoint);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw ChatGenerationException(
          'API URL 协议不支持（需要 http/https）：$endpoint',
          protocol: request.target.protocol,
        );
      }
      return uri;
    } on FormatException catch (error) {
      throw ChatGenerationException(
        'API URL 格式无效：${error.message}',
        protocol: request.target.protocol,
      );
    }
  }
}
