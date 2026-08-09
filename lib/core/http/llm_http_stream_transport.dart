import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'sse_event_decoder.dart';

/// 流式 LLM HTTP 传输异常。
///
/// 传输层只封装传输与响应边界问题（连接、状态码、错误体、超时），
/// 不解析任何协议 JSON；协议客户端负责把本异常转换为业务异常。
class LlmHttpTransportException implements Exception {
  const LlmHttpTransportException(
    this.message, {
    this.statusCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });

  final String message;

  /// HTTP 状态码（非 2xx 响应时可用）。
  final int? statusCode;

  /// 原始响应体（HTTP 错误时保留服务端原文）。
  final String? responseBody;

  /// 被包装的源异常（连接中断、TLS 握手失败、超时等）。
  final Object? cause;

  /// 源异常对应的堆栈。
  final StackTrace? causeStackTrace;

  @override
  String toString() => message;
}

/// 共享流式 HTTP 传输：发起流式 POST 并把响应解码为 SSE 事件。
///
/// 职责：发起请求、取消底层请求、连接异常包装、SSE 行与事件边界解码
/// （复用 [SseEventDecoder]）、idle timeout、网络日志与敏感字段脱敏。
/// 本类不读取任何具体协议 JSON 字段。
class LlmHttpStreamTransport {
  LlmHttpStreamTransport({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
    SseEventDecoder decoder = const SseEventDecoder(),
  }) : _httpClient = httpClient,
       _logger = logger,
       _extraHeadersFactory = extraHeadersFactory,
       _decoder = decoder;

  final http.Client _httpClient;
  final NetworkLogger _logger;
  final Map<String, String> Function()? _extraHeadersFactory;
  final SseEventDecoder _decoder;

  /// 发起流式 POST 并把响应体解码为 [SseEvent] 流。
  ///
  /// [headers] 由调用方构造（含认证头）；用户自定义 Header 的实际注入由
  /// CustomHeadersHttpClient 统一完成，此处只读取其值参与日志合并。
  /// [idleTimeout] 非空时，SSE 流在该时长内没有新 `data:` 行则抛出
  /// [LlmHttpTransportException]。
  Stream<SseEvent> streamEvents({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    Duration? idleTimeout,
  }) async* {
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = body;

    // 读取自定义 header 供日志使用；实际注入由 CustomHeadersHttpClient.send() 完成。
    final extraHeaders =
        _extraHeadersFactory?.call() ?? const <String, String>{};
    unawaited(
      _logger.logRequest(
        uri: uri,
        method: request.method,
        headers: {...request.headers, ...extraHeaders},
        payload: body,
        // 请求正文默认不记录，避免扩大日志采集。
        logBody: false,
      ),
    );

    final requestStartedAt = DateTime.now();
    final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } catch (error, stackTrace) {
      unawaited(
        _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
      );
      // 包装源异常并保留原始堆栈，供上层展示完整诊断信息。
      throw LlmHttpTransportException(
        '请求发送失败：$error',
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    unawaited(
      _logger.logResponse(
        uri: uri,
        statusCode: response.statusCode,
        headers: response.headers,
        elapsed: DateTime.now().difference(requestStartedAt),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String responseBody;
      try {
        responseBody = await response.stream.bytesToString();
      } catch (error, stackTrace) {
        unawaited(
          _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
        );
        throw LlmHttpTransportException(
          '读取错误响应体失败：$error',
          cause: error,
          causeStackTrace: stackTrace,
        );
      }
      final trimmedBody = responseBody.trim();
      unawaited(
        _logger.logError(
          uri: uri,
          error:
              'HTTP ${response.statusCode}: ${trimmedBody.isEmpty ? "服务端未返回错误详情" : trimmedBody}',
        ),
      );
      // 非 2xx：封装状态码与原始错误体，协议层再提取厂商错误详情。
      throw LlmHttpTransportException(
        '请求失败（${response.statusCode}）：${trimmedBody.isEmpty ? "服务端未返回错误详情" : trimmedBody}',
        statusCode: response.statusCode,
        responseBody: trimmedBody.isEmpty ? null : trimmedBody,
      );
    }

    final eventStream = _decoder.decode(
      response.stream,
      idleTimeout: idleTimeout,
    );
    try {
      await for (final event in eventStream) {
        _logSseEvent(uri, event);
        yield event;
      }
    } on TimeoutException catch (error, stackTrace) {
      unawaited(
        _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
      );
      throw LlmHttpTransportException(
        '服务器在 ${idleTimeout?.inSeconds ?? 0} 秒内没有响应，连接超时',
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      unawaited(
        _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
      );
      // 流中途的连接中断、解码失败等统一包装为传输异常。
      throw LlmHttpTransportException(
        '流式响应读取失败：$error',
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// 逐行记录事件原始 data 文本（含 `data:` 前缀），供缓冲日志诊断。
  void _logSseEvent(Uri uri, SseEvent event) {
    for (final line in event.rawData.split('\n')) {
      unawaited(_logger.logSseLine(uri: uri, line: line));
    }
  }
}
