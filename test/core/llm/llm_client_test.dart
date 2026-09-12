import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';

const _target = LlmRequestTarget(
  protocol: LlmApiProtocol.chatCompletions,
  endpoint: 'https://example.com',
  apiKey: 'test',
  model: 'test',
);

void main() {
  test('输入和嵌套工具 schema 在构造后保持不可变', () {
    final schema = <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        '角色': {'type': 'string'},
      },
    };
    final tool = LlmToolDefinition(
      name: 'read',
      description: '读取',
      parameters: schema,
    );
    (schema['properties'] as Map).clear();
    expect(tool.parameters['properties'], isNotEmpty);
    expect(
      () => (tool.parameters['properties'] as Map).clear(),
      throwsUnsupportedError,
    );
    final input = <LlmInputItem>[
      const LlmTextMessage(role: LlmRole.user, text: '你好'),
    ];
    final request = LlmRequest(target: _target, input: input);
    input.clear();
    expect(request.input, hasLength(1));
  });

  test('JSON 边界拒绝自定义对象和循环引用', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    for (final value in [
      Object(),
      _JsonObject(),
      cycle,
      double.nan,
      <Object, Object>{1: '值'},
    ]) {
      expect(
        () => immutableLlmJson(value),
        throwsA(
          isA<LlmException>().having(
            (e) => e.kind,
            '类型',
            LlmFailureKind.invalidRequest,
          ),
        ),
      );
    }
  });

  for (final mode in ['缺失结果', '未知结果', '重复结果', '名称不符', '切换模型', '参数不符']) {
    test('$mode 在发送前失败', () async {
      final httpClient = _Http();
      final client = ChatCompletionsClient(
        transport: LlmHttpStreamTransport(httpClient: httpClient),
      );
      // 原生回放 fixture 是协议边界数据；上层仍用 typed turn 和 result。
      final turn = LlmAssistantTurn(
        replay: LlmReplayEnvelope(
          protocol: LlmApiProtocol.chatCompletions,
          endpoint: Uri.parse('https://example.com/v1/chat/completions'),
          model: mode == '切换模型' ? 'other' : 'test',
          items: [
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'type': 'function',
                  'id': 'a',
                  'function': {'name': 'read', 'arguments': '{}'},
                },
              ],
            },
          ],
        ),
        toolCalls: [
          LlmToolCall(
            callId: 'a',
            name: 'read',
            argumentsJson: mode == '参数不符' ? '{"x":1}' : '{}',
          ),
        ],
      );
      final result = LlmToolResult(
        callId: mode == '未知结果' ? 'b' : 'a',
        name: mode == '名称不符' ? 'write' : 'read',
        output: '角色卡',
      );
      await expectLater(
        client.complete(
          LlmRequest(
            target: _target,
            input: [
              turn,
              if (mode != '缺失结果') result,
              if (mode == '重复结果') result,
            ],
          ),
        ),
        throwsA(
          isA<LlmException>().having(
            (e) => e.kind,
            '类型',
            LlmFailureKind.invalidRequest,
          ),
        ),
      );
      expect(httpClient.sends, 0);
    });
  }

  test('流在订阅前不发送且完成对象不会重复追加正文', () async {
    final httpClient = _Http();
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(httpClient: httpClient),
    );
    final stream = client.streamCompletion(
      LlmRequest(target: _target, input: []),
    );
    expect(httpClient.sends, 0);
    final events = await stream.toList();
    expect(httpClient.sends, 1);
    expect(events.whereType<LlmCompleted>(), hasLength(1));
    expect(events.map((e) => e.contentDelta).join(), '正文');
    expect(events.whereType<LlmCompleted>().single.result.content, '正文');
    expect(() => stream.listen((_) {}), throwsStateError);
  });

  test('工具参数和工具结果按 UTF8 字节限制', () {
    final large = List.filled(maxLlmToolBytes ~/ 3 + 1, '甲').join();
    expect(
      () => LlmToolCall(
        callId: 'a',
        name: 'read',
        argumentsJson: jsonEncode({'x': large}),
      ),
      throwsA(isA<LlmException>()),
    );
    expect(
      () => LlmToolResult(callId: 'a', name: 'read', output: large),
      throwsA(isA<LlmException>()),
    );
  });
}

class _Http extends http.BaseClient {
  int sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"正文"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
        ),
      ),
      200,
    );
  }
}

class _JsonObject {
  Map<String, Object> toJson() => {};
}
