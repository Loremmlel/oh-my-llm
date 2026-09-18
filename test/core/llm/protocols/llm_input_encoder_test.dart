import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_input_encoder.dart';

LlmRequest _request(
  LlmApiProtocol protocol, {
  LlmToolChoice choice = const LlmToolChoice.auto(),
  bool withTools = true,
  LlmGenerationOptions options = const LlmGenerationOptions(),
}) => LlmRequest(
  target: LlmRequestTarget(
    protocol: protocol,
    endpoint: 'https://example.com',
    apiKey: 'test',
    model: 'test',
  ),
  input: [],
  tools: [
    if (withTools)
      LlmToolDefinition(
        name: 'read',
        description: '读取',
        parameters: {'type': 'object'},
      ),
  ],
  toolChoice: choice,
  parallelToolCalls: false,
  options: options,
);

void main() {
  test('Responses 续接保留 assistant 阶段且不向用户消息添加阶段', () {
    final endpoint = Uri.parse('https://example.com');
    final request = LlmRequest(
      target: _request(LlmApiProtocol.responses).target,
      input: [
        const LlmTextMessage(role: LlmRole.user, text: '继续'),
        LlmAssistantTurn(
          text: '完成',
          replay: LlmReplayEnvelope(
            protocol: LlmApiProtocol.responses,
            endpoint: endpoint,
            model: 'test',
            items: [
              for (final phase in ['commentary', 'final_answer'])
                {
                  'type': 'message',
                  'role': 'assistant',
                  'phase': phase,
                  'content': [
                    {'type': 'output_text', 'text': phase},
                  ],
                },
            ],
          ),
        ),
      ],
    );
    final input = encodeLlmInput(request, endpoint)['input'] as List;
    expect((input.first as Map).containsKey('phase'), isFalse);
    expect(input[1]['phase'], 'commentary');
    expect(input[2]['phase'], 'final_answer');
  });
  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 从公共历史编码正文、函数调用与结果', () {
      final turn = LlmAssistantTurn.portable(
        text: '读取正文',
        toolCalls: [
          LlmToolCall(callId: 'read_1', name: 'read', argumentsJson: '{}'),
        ],
      );
      final wire = encodeLlmInput(
        LlmRequest(
          target: _request(protocol).target,
          input: [
            turn,
            LlmToolResult(callId: 'read_1', name: 'read', output: '正文'),
          ],
        ),
        Uri.parse('https://example.com'),
      );
      expect(wire, switch (protocol) {
        LlmApiProtocol.chatCompletions => {
          'messages': [
            {
              'role': 'assistant',
              'content': '读取正文',
              'tool_calls': [
                {
                  'id': 'read_1',
                  'type': 'function',
                  'function': {'name': 'read', 'arguments': '{}'},
                },
              ],
            },
            {'role': 'tool', 'tool_call_id': 'read_1', 'content': '正文'},
          ],
        },
        LlmApiProtocol.responses => {
          'input': [
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': '读取正文', 'annotations': []},
              ],
            },
            {
              'type': 'function_call',
              'call_id': 'read_1',
              'name': 'read',
              'arguments': '{}',
            },
            {
              'type': 'function_call_output',
              'call_id': 'read_1',
              'output': '正文',
            },
          ],
        },
        LlmApiProtocol.anthropic => {
          'messages': [
            {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': '读取正文'},
                {
                  'type': 'tool_use',
                  'id': 'read_1',
                  'name': 'read',
                  'input': {},
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 'read_1',
                  'content': '正文',
                  'is_error': false,
                },
              ],
            },
          ],
        },
      });
      expect(turn.replay, isNull);
    });
    for (final choice in [
      const LlmToolChoice.auto(),
      const LlmToolChoice.none(),
      const LlmToolChoice.required(),
      const LlmToolChoice.named('read'),
    ]) {
      test('${protocol.name} 正确表达 ${choice.kind.name} 与并行限制', () {
        final wire = encodeLlmTools(_request(protocol, choice: choice));
        // 原生选择结构是 wire 契约，不用其他 encoder 生成预期值。
        if (protocol == LlmApiProtocol.anthropic) {
          expect(wire['tool_choice'], switch (choice.kind) {
            LlmToolChoiceKind.auto => {
              'type': 'auto',
              'disable_parallel_tool_use': true,
            },
            LlmToolChoiceKind.none => {'type': 'none'},
            LlmToolChoiceKind.required => {
              'type': 'any',
              'disable_parallel_tool_use': true,
            },
            LlmToolChoiceKind.named => {
              'type': 'tool',
              'name': 'read',
              'disable_parallel_tool_use': true,
            },
          });
        } else {
          expect(wire['parallel_tool_calls'], false);
          expect(
            wire['tool_choice'],
            choice.kind == LlmToolChoiceKind.named
                ? (protocol == LlmApiProtocol.responses
                      ? {'type': 'function', 'name': 'read'}
                      : {
                          'type': 'function',
                          'function': {'name': 'read'},
                        })
                : choice.kind.name,
          );
        }
      });
    }
    test('${protocol.name} 未配置缓存不发送缓存字段', () {
      final wire = encodeLlmOptions(_request(protocol));
      expect(wire, isEmpty);
    });
  }
  for (final scenario in ['缺失结果', '未知结果', '重复结果', '名称不符', '重复调用']) {
    test('公共历史拒绝工具往返中的$scenario', () {
      final call = LlmToolCall(
        callId: 'call',
        name: 'read',
        argumentsJson: '{}',
      );
      final result = LlmToolResult(callId: 'call', name: 'read', output: '正文');
      final input = <LlmInputItem>[
        LlmAssistantTurn.portable(
          toolCalls: [call, if (scenario == '重复调用') call],
        ),
        if (scenario != '缺失结果')
          LlmToolResult(
            callId: scenario == '未知结果' ? 'unknown' : 'call',
            name: scenario == '名称不符' ? 'other' : 'read',
            output: '正文',
          ),
        if (scenario == '重复结果') result,
      ];
      expect(
        () => encodeLlmInput(
          LlmRequest(
            target: _request(LlmApiProtocol.responses).target,
            input: input,
          ),
          Uri.parse('https://example.com'),
        ),
        throwsA(
          isA<LlmException>().having(
            (e) => e.kind,
            '类型',
            LlmFailureKind.invalidRequest,
          ),
        ),
      );
    });
  }
  test('无工具时省略 auto 和 none，拒绝 required 和 named', () {
    for (final choice in [
      const LlmToolChoice.auto(),
      const LlmToolChoice.none(),
    ]) {
      final request = _request(
        LlmApiProtocol.chatCompletions,
        choice: choice,
        withTools: false,
      );
      expect(encodeLlmTools(request), isEmpty);
      expect(
        () => encodeLlmInput(request, Uri.parse('https://example.com')),
        returnsNormally,
      );
    }
    for (final choice in [
      const LlmToolChoice.required(),
      const LlmToolChoice.named('read'),
    ]) {
      expect(
        () => encodeLlmInput(
          _request(
            LlmApiProtocol.chatCompletions,
            choice: choice,
            withTools: false,
          ),
          Uri.parse('https://example.com'),
        ),
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
  test('自动缓存支持五分钟且未启用时拒绝 TTL', () {
    expect(
      encodeLlmOptions(
        _request(
          LlmApiProtocol.anthropic,
          options: const LlmGenerationOptions(
            protocolOptions: MessagesOptions(
              automaticCacheControl: true,
              cacheTtl: MessagesCacheTtl.fiveMinutes,
            ),
          ),
        ),
      ),
      {
        'cache_control': {'type': 'ephemeral', 'ttl': '5m'},
      },
    );
    expect(
      () => encodeLlmOptions(
        _request(
          LlmApiProtocol.anthropic,
          options: const LlmGenerationOptions(
            protocolOptions: MessagesOptions(
              cacheTtl: MessagesCacheTtl.fiveMinutes,
            ),
          ),
        ),
      ),
      throwsA(isA<LlmException>()),
    );
  });
}
