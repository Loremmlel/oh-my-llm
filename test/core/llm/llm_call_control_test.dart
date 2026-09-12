import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';

LlmRequest _request({
  String endpoint = 'https://example.com',
  Duration? timeout,
}) => LlmRequest(
  target: LlmRequestTarget(
    protocol: LlmApiProtocol.chatCompletions,
    endpoint: endpoint,
    apiKey: 'test',
    model: 'test',
  ),
  input: const [LlmTextMessage(role: LlmRole.user, text: '你好')],
  options: LlmGenerationOptions(responseHeaderTimeout: timeout),
);

void main() {
  test('订阅前取消不发送且句柄不能复用', () async {
    var sends = 0;
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((_) async {
          sends++;
          return _ok();
        }),
      ),
    );
    final control = LlmCallControl()
      ..cancel()
      ..cancel();
    await expectLater(
      client.complete(_request(), control: control),
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '类型',
          LlmFailureKind.cancelled,
        ),
      ),
    );
    expect(sends, 0);
    await expectLater(
      client.complete(_request(), control: control),
      throwsStateError,
    );
  });

  test('一个调用取消后其他并发调用及后续调用仍完成', () async {
    final started = Completer<void>();
    final delayed = Completer<http.StreamedResponse>();
    var sends = 0;
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((_) async {
          sends++;
          if (sends == 1) {
            started.complete();
            return delayed.future;
          }
          return _ok();
        }),
      ),
    );
    final control = LlmCallControl();
    final first = client.complete(_request(), control: control);
    final failure = expectLater(
      first,
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '类型',
          LlmFailureKind.cancelled,
        ),
      ),
    );
    await started.future;
    expect((await client.complete(_request())).content, 'ok');
    control.cancel();
    await failure.timeout(const Duration(seconds: 1));
    expect((await client.complete(_request())).content, 'ok');
    delayed.complete(_ok());
    expect(sends, 3);
  });

  test('响应头等待超时释放调用并接住迟到响应', () async {
    final delayed = Completer<http.StreamedResponse>();
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((_) => delayed.future),
      ),
    );
    try {
      await expectLater(
        client.complete(_request(timeout: const Duration(milliseconds: 20))),
        throwsA(
          isA<LlmException>().having(
            (e) => e.kind,
            '类型',
            LlmFailureKind.timeout,
          ),
        ),
      ).timeout(const Duration(seconds: 1));
    } finally {
      delayed.complete(_ok());
    }
  });

  test('非成功响应体停住时取消仍释放请求且不执行兼容重发', () async {
    final listened = Completer<void>();
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(
      onListen: listened.complete,
      onCancel: cancelled.complete,
    );
    var sends = 0;
    final control = LlmCallControl();
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((_) async {
          sends++;
          return http.StreamedResponse(body.stream, 400);
        }),
      ),
    );
    final failure = expectLater(
      client.complete(_request(), control: control),
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '类型',
          LlmFailureKind.cancelled,
        ),
      ),
    );
    try {
      await listened.future;
      body.add(utf8.encode('include_usage unsupported'));
      control.cancel();
      await failure.timeout(const Duration(seconds: 1));
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(sends, 1);
    } finally {
      control.cancel();
      await body.close();
    }
  });

  test('真实 HTTP 首段 SSE 后静默时取消释放请求且客户端可再次使用', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final httpClient = CustomHeadersHttpClient(http.Client(), {});
    var received = 0;
    final requests = server.listen((request) async {
      await request.drain<void>();
      received++;
      // 小片段必须立即写到 socket，才能验证首段后的静默取消。
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
      );
      await request.response.flush();
      if (received > 1) await request.response.close();
    });
    final llm = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(httpClient: httpClient),
    );
    final first = Completer<void>();
    final request = _request(endpoint: 'http://127.0.0.1:${server.port}');
    final subscription = llm.streamCompletion(request).listen((event) {
      if (event.contentDelta.isNotEmpty && !first.isCompleted) first.complete();
    });
    try {
      await first.future.timeout(const Duration(seconds: 2));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(
        (await llm.complete(request).timeout(const Duration(seconds: 2)))
            .content,
        'ok',
      );
    } finally {
      await subscription.cancel();
      httpClient.close();
      await server.close(force: true);
      await requests.cancel();
    }
  });

  test('真实 HTTP 经自定义 Header 包装后仍可在响应头前取消', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = CustomHeadersHttpClient(http.Client(), {
      'X-Test': 'forwarded',
    });
    final arrived = Completer<void>();
    final requests = server.listen((request) async {
      await request.drain<void>();
      expect(request.headers.value('X-Test'), 'forwarded');
      arrived.complete();
    });
    final llm = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(httpClient: client),
    );
    final control = LlmCallControl();
    final result = llm.complete(
      _request(endpoint: 'http://127.0.0.1:${server.port}'),
      control: control,
    );
    final failure = expectLater(
      result,
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '类型',
          LlmFailureKind.cancelled,
        ),
      ),
    );
    try {
      await arrived.future.timeout(const Duration(seconds: 2));
      control.cancel();
      await failure.timeout(const Duration(seconds: 1));
    } finally {
      control.cancel();
      client.close();
      await server.close(force: true);
      await requests.cancel();
    }
  });
}

http.StreamedResponse _ok() => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
    ),
  ),
  200,
);

class _Http extends http.BaseClient {
  _Http(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
