import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
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
    this.kind = LlmFailureKind.transport,
  });

  final String message;
  final LlmFailureKind kind;

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
    required this._httpClient,
    this._logger = const NoopNetworkLogger(),
    this._extraHeadersFactory,
    this._decoder = const SseEventDecoder(),
  });

  final http.Client _httpClient;
  final NetworkLogger _logger;
  final Map<String, String> Function()? _extraHeadersFactory;
  final SseEventDecoder _decoder;

  /// 完整调用摘要不含正文、工具参数或原生推理块。
  void recordCompletion({
    required String requestId,
    required String protocol,
    required String model,
    required String stopKind,
    required int toolCallCount,
    required Duration elapsed,
    LlmUsage? usage,
  }) {
    unawaited(
      _logger.logLlmCompletion(
        requestId: requestId,
        protocol: protocol,
        model: model,
        stopKind: stopKind,
        toolCallCount: toolCallCount,
        elapsed: elapsed,
        usage: usage,
      ),
    );
  }

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
    Duration? responseHeaderTimeout,
    LlmCallControl? control,
    bool logRawResponse = true,
    String? requestId,
    int? attempt,
  }) {
    late StreamController<SseEvent> output;
    StreamSubscription<SseEvent>? events;
    StreamSubscription<List<int>>? errorBody;
    Timer? headerTimer;
    Timer? bodyTimer;
    final abort = Completer<void>();
    var stopped = false;
    void Function()? removeCancelListener;

    void release() {
      headerTimer?.cancel();
      bodyTimer?.cancel();
      removeCancelListener?.call();
      if (!abort.isCompleted) abort.complete();
      final eventSubscription = events;
      final bodySubscription = errorBody;
      if (eventSubscription != null) unawaited(eventSubscription.cancel());
      if (bodySubscription != null) unawaited(bodySubscription.cancel());
    }

    void fail(Object error, [StackTrace? stack]) {
      if (stopped) return;
      stopped = true;
      final converted = error is LlmHttpTransportException
          ? error
          : LlmHttpTransportException(
              error is TimeoutException ? '服务器响应超时' : '请求失败：$error',
              kind: error is TimeoutException
                  ? LlmFailureKind.timeout
                  : LlmFailureKind.transport,
              cause: error,
              causeStackTrace: stack,
            );
      unawaited(
        _logger.logError(
          requestId: requestId,
          attempt: attempt,
          uri: uri,
          error: logRawResponse ? converted.message : converted.kind.name,
          stackTrace: logRawResponse ? stack : null,
        ),
      );
      output.addError(converted, stack);
      release();
      unawaited(output.close());
    }

    Future<void> start() async {
      removeCancelListener = control?.onCancel(
        () => fail(
          const LlmHttpTransportException(
            '调用已取消',
            kind: LlmFailureKind.cancelled,
          ),
        ),
      );
      if (stopped) return;
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: abort.future)
            ..headers.addAll(headers)
            ..body = body;
      final extraHeaders =
          _extraHeadersFactory?.call() ?? const <String, String>{};
      unawaited(
        _logger.logRequest(
          requestId: requestId,
          attempt: attempt,
          uri: uri,
          method: request.method,
          headers: {...request.headers, ...extraHeaders},
          payload: body,
          logBody: false,
        ),
      );
      final startedAt = DateTime.now();
      if (responseHeaderTimeout != null) {
        headerTimer = Timer(
          responseHeaderTimeout,
          () => fail(TimeoutException('等待响应头超时', responseHeaderTimeout)),
        );
      }
      try {
        final response = await _httpClient.send(request);
        headerTimer?.cancel();
        if (stopped) {
          await response.stream.listen((_) {}).cancel();
          return;
        }
        unawaited(
          _logger.logResponse(
            requestId: requestId,
            attempt: attempt,
            uri: uri,
            statusCode: response.statusCode,
            headers: response.headers,
            elapsed: DateTime.now().difference(startedAt),
          ),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final bytes = <int>[];
          void resetBodyTimer() {
            bodyTimer?.cancel();
            final timeout = idleTimeout ?? responseHeaderTimeout;
            if (timeout != null) {
              bodyTimer = Timer(
                timeout,
                () => fail(TimeoutException('读取错误响应体超时', timeout)),
              );
            }
          }

          resetBodyTimer();
          errorBody = response.stream.listen(
            (chunk) {
              resetBodyTimer();
              // 错误体只保留有界诊断尾部，防止异常服务无限占用内存。
              bytes.addAll(chunk);
              if (bytes.length > 1024 * 1024) {
                bytes.removeRange(0, bytes.length - 1024 * 1024);
              }
            },
            onError: fail,
            onDone: () {
              final text = utf8.decode(bytes, allowMalformed: true).trim();
              fail(
                LlmHttpTransportException(
                  '请求失败（${response.statusCode}）：${text.isEmpty ? "服务端未返回错误详情" : text}',
                  statusCode: response.statusCode,
                  responseBody: text.isEmpty ? null : text,
                ),
              );
            },
          );
          return;
        }
        events = _decoder
            .decode(response.stream, idleTimeout: idleTimeout)
            .listen(
              (event) {
                if (stopped) return;
                if (logRawResponse) {
                  for (final line in event.rawData.split('\n')) {
                    unawaited(
                      _logger.logSseLine(
                        requestId: requestId,
                        attempt: attempt,
                        uri: uri,
                        line: line,
                      ),
                    );
                  }
                }
                output.add(event);
              },
              onError: fail,
              onDone: () {
                if (stopped) return;
                stopped = true;
                release();
                unawaited(output.close());
              },
            );
      } catch (error, stack) {
        fail(error, stack);
      }
    }

    output = StreamController<SseEvent>(
      onListen: () {
        unawaited(
          start().catchError(
            (Object error, StackTrace stack) => fail(error, stack),
          ),
        );
      },
      onPause: () => events?.pause(),
      onResume: () => events?.resume(),
      onCancel: () {
        stopped = true;
        release();
      },
    );
    return output.stream;
  }
}
