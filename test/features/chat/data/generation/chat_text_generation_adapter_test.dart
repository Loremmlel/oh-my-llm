import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_text_generation_adapter.dart';

const _request = ChatGenerationRequest(
  target: ChatGenerationRequestTarget(
    protocol: LlmApiProtocol.chatCompletions,
    endpoint: 'https://example.com',
    apiKey: 'test',
    model: 'test',
  ),
  messages: [],
);

void main() {
  test('聊天适配器拆分跨片段标签且不重复追加最终正文', () async {
    final core = _Client(
      (request, control) => Stream.fromIterable([
        const LlmEvent(contentDelta: '<thi'),
        const LlmEvent(contentDelta: 'nking>推理</thinking>正文'),
        LlmCompleted(const LlmResult(content: '<thinking>推理</thinking>正文')),
      ]),
    );
    final result = await ChatTextGenerationAdapter(core).complete(_request);
    expect(result.content, '正文');
    expect(result.reasoningContent, '推理');
    expect(core.request!.tools, isEmpty);
    expect(
      core.request!.options.responseHeaderTimeout,
      const Duration(seconds: 60),
    );
    expect(core.request!.options.maxOutputTokens, isNull);
  });

  test('共享空结果转换为聊天空回复异常', () async {
    final core = _Client(
      (_, _) =>
          Stream.value(LlmCompleted(const LlmResult(diagnosticBody: '诊断'))),
    );
    await expectLater(
      ChatTextGenerationAdapter(core).complete(_request),
      throwsA(
        isA<ChatGenerationException>()
            .having((e) => e.message, '消息', '请求未返回有效内容')
            .having((e) => e.responseBody, '诊断', '诊断'),
      ),
    );
  });

  test('聊天停止在共享流没有后续事件时仍传播取消', () async {
    final started = Completer<void>();
    final source = StreamController<LlmEvent>();
    late LlmCallControl captured;
    final core = _Client((_, control) {
      captured = control;
      started.complete();
      return source.stream;
    });
    final subscription = ChatTextGenerationAdapter(core)
        .streamCompletion(_request)
        .listen((_) {});
    try {
      await started.future;
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(captured.isCancelled, isTrue);
    } finally {
      await subscription.cancel();
      await source.close();
    }
  });
}

class _Client extends LlmClient {
  _Client(this.handler);
  final Stream<LlmEvent> Function(LlmRequest, LlmCallControl) handler;
  LlmRequest? request;
  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) {
    this.request = request;
    return handler(request, control);
  }
}
