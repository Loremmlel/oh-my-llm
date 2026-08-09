import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';

void main() {
  final testUri = Uri.parse('https://api.example.com/v1/chat/completions');
  const testHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Authorization': 'Bearer sk-test-12345678',
  };

  test('流式 POST 请求参数透传并解码为事件流', () async {
    final client = _FakeStreamingHttpClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, testUri);
      expect(request.headers['Authorization'], 'Bearer sk-test-12345678');
      expect(jsonDecode((request as http.Request).body), {
        'model': 'gpt-4.1',
        'stream': true,
      });
      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode('data: {"a":1}\n\n'),
          utf8.encode('data: {"b":2}\n\n'),
        ]),
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    final events = await transport
        .streamEvents(
          uri: testUri,
          headers: testHeaders,
          body: '{"model":"gpt-4.1","stream":true}',
        )
        .toList();

    expect(events, hasLength(2));
    expect(events.map((e) => e.data).toList(), ['{"a":1}', '{"b":2}']);
  });

  test('请求日志合并自定义 header，正文默认不记录，SSE 行按行记录', () async {
    final logger = _FakeNetworkLogger();
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('data: a\ndata: b\n\n')]),
        200,
      );
    });
    final transport = LlmHttpStreamTransport(
      httpClient: client,
      logger: logger,
      extraHeadersFactory: () => const {'X-Custom-Header': 'custom-value'},
    );

    await transport
        .streamEvents(uri: testUri, headers: testHeaders, body: '{"s":1}')
        .drain<void>();

    expect(logger.requestCount, 1);
    expect(logger.requestHeaders!['Authorization'], 'Bearer sk-test-12345678');
    expect(logger.requestHeaders!['X-Custom-Header'], 'custom-value');
    expect(logger.requestLogBody, isFalse);
    expect(logger.responseCount, 1);
    expect(logger.sseCount, 2);
    expect(logger.errorCount, 0);
  });

  test('非 2xx 抛出传输异常并保留原始错误体', () async {
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"bad key"}}')),
        401,
      );
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    await expectLater(
      transport
          .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
          .toList(),
      throwsA(
        isA<LlmHttpTransportException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having(
              (e) => e.responseBody,
              'responseBody',
              '{"error":{"message":"bad key"}}',
            )
            .having((e) => e.message, 'message', contains('401')),
      ),
    );
  });

  test('非 2xx 空错误体时 responseBody 为 null', () async {
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(Stream.value(utf8.encode('   ')), 503);
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    await expectLater(
      transport
          .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
          .toList(),
      throwsA(
        isA<LlmHttpTransportException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.responseBody, 'responseBody', isNull)
            .having((e) => e.message, 'message', contains('服务端未返回错误详情')),
      ),
    );
  });

  test('连接异常包装为传输异常并保留 cause 与堆栈', () async {
    final connectionError = http.ClientException('connection refused', testUri);
    final client = _FakeStreamingHttpClient((_) async {
      throw connectionError;
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    await expectLater(
      transport
          .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
          .toList(),
      throwsA(
        isA<LlmHttpTransportException>()
            .having((e) => e.cause, 'cause', same(connectionError))
            .having((e) => e.causeStackTrace, 'causeStackTrace', isNotNull)
            .having(
              (e) => e.message,
              'message',
              contains('connection refused'),
            ),
      ),
    );
  });

  test('流中途连接中断包装为传输异常', () async {
    final source = StreamController<List<int>>();
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(source.stream, 200);
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    final events = <SseEvent>[];
    final errors = <Object>[];
    final subscription = transport
        .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
        .listen(events.add, onError: errors.add);

    source.add(utf8.encode('data: {"a":1}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));

    source.addError(http.ClientException('connection reset', testUri));
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<LlmHttpTransportException>());
    expect(
      (errors.single as LlmHttpTransportException).cause,
      isA<http.ClientException>(),
    );

    await subscription.cancel();
    await source.close();
  });

  test('SSE 空闲超时包装为传输异常', () async {
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode('data: x\n\n')),
        200,
      );
    });
    // 解码器的计时语义由 decoder 层测试用 fakeAsync 精确覆盖；
    // 这里注入立即超时的假解码器，确定性地验证超时错误到传输异常的转换。
    final transport = LlmHttpStreamTransport(
      httpClient: client,
      decoder: _TimeoutDecoder(),
    );

    final errors = <Object>[];
    final events = <SseEvent>[];
    final subscription = transport
        .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
        .listen(events.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<LlmHttpTransportException>());
    final exception = errors.single as LlmHttpTransportException;
    expect(exception.cause, isA<TimeoutException>());
    expect(exception.message, contains('超时'));

    await subscription.cancel();
  });

  test('取消订阅释放底层 HTTP byte stream', () async {
    final source = StreamController<List<int>>();
    final client = _FakeStreamingHttpClient((_) async {
      return http.StreamedResponse(source.stream, 200);
    });
    final transport = LlmHttpStreamTransport(httpClient: client);

    final subscription = transport
        .streamEvents(uri: testUri, headers: testHeaders, body: '{}')
        .listen((_) {});

    // 等底层 byte stream 订阅建立。
    await Future<void>.delayed(Duration.zero);
    expect(source.hasListener, isTrue);

    source.add(utf8.encode('data: x\n\n'));
    await Future<void>.delayed(Duration.zero);

    final cancelFuture = subscription.cancel();

    // async* 生成器暂停在 yield 处，需下一个网络 chunk 将其唤醒后才执行
    // 取消；这与既有 OpenAiCompatibleChatClient 的取消语义一致（停止按钮
    // 依赖流中仍有数据在流动）。
    source.add(utf8.encode('data: y\n\n'));
    await cancelFuture.timeout(const Duration(seconds: 5));

    expect(source.hasListener, isFalse);
    await source.close();
  });
}

class _FakeStreamingHttpClient extends http.BaseClient {
  _FakeStreamingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

/// 立即抛出超时错误的假解码器，用于确定性地测试超时转换。
class _TimeoutDecoder extends SseEventDecoder {
  const _TimeoutDecoder();

  @override
  Stream<SseEvent> decode(
    Stream<List<int>> byteStream, {
    Duration? idleTimeout,
  }) {
    return Stream.error(TimeoutException('fake idle timeout'));
  }
}

final class _FakeNetworkLogger with NetworkLogger {
  int requestCount = 0;
  int responseCount = 0;
  int sseCount = 0;
  int errorCount = 0;
  Map<String, String>? requestHeaders;
  bool? requestLogBody;

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
    bool logBody = false,
  }) async {
    requestCount += 1;
    requestHeaders = headers;
    requestLogBody = logBody;
  }

  @override
  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {
    responseCount += 1;
  }

  @override
  Future<void> logSseLine({required Uri uri, required String line}) async {
    sseCount += 1;
  }

  @override
  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    errorCount += 1;
  }
}
