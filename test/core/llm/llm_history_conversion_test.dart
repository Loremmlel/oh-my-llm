import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';
import 'package:oh_my_llm/core/llm/llm_history_conversion.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_input_encoder.dart';

void main() {
  for (final source in LlmApiProtocol.values) {
    for (final destination in LlmApiProtocol.values) {
      test('${source.name} 转 ${destination.name} 保留文本及完整工具往返并丢弃私有字段', () {
        final target = LlmRequestTarget(
          protocol: destination,
          endpoint: 'https://new.example/v1',
          apiKey: '',
          model: 'new-model',
        );
        final original = LlmAssistantTurn(
          text: '可见回答',
          reasoning: '不可迁移推理',
          toolCalls: [
            LlmToolCall(
              callId: 'vendor:call/1',
              name: 'read_document',
              argumentsJson: '{"name":"正文"}',
            ),
            LlmToolCall(
              callId: 'omll_0',
              name: 'read_document',
              argumentsJson: '{"name":"设定"}',
            ),
          ],
          replay: LlmReplayEnvelope(
            protocol: source,
            endpoint: Uri.parse('https://old.example'),
            model: 'old-model',
            items: [
              {'type': 'thinking', 'thinking': '不可迁移推理', 'signature': '不兼容签名'},
              {'type': 'reasoning', 'encrypted_content': '不兼容加密'},
              {'type': 'web_search_call', 'id': '厂商内置工具'},
            ],
          ),
        );
        final history = <LlmInputItem>[
          const LlmTextMessage(role: LlmRole.user, text: '继续'),
          original,
          LlmToolResult(
            callId: 'vendor:call/1',
            name: 'read_document',
            output: '正文内容',
          ),
          LlmToolResult(
            callId: 'omll_0',
            name: 'read_document',
            output: '读取失败',
            isError: true,
          ),
        ];
        final converted = convertLlmHistory(history, target);
        expect(converted, hasLength(history.length));
        final turn = converted[1] as LlmAssistantTurn;
        expect(turn.reasoning, isEmpty);
        expect(turn.toolCalls.map((c) => c.callId).toSet(), hasLength(2));
        expect(turn.toolCalls.first.callId, isNot('omll_0'));
        expect(
          (converted[2] as LlmToolResult).callId,
          turn.toolCalls.first.callId,
        );
        expect((converted[3] as LlmToolResult).isError, isTrue);
        final endpoint = const LlmEndpointResolver().resolveGenerationEndpoint(
          rawUrl: target.endpoint,
          protocol: destination,
        );
        final encoded = jsonEncode(
          encodeLlmInput(
            LlmRequest(target: target, input: converted),
            endpoint,
          ),
        );
        for (final text in ['可见回答', '正文内容', '读取失败', 'read_document']) {
          expect(encoded, contains(text));
        }
        for (final text in ['不可迁移推理', '不兼容签名', '不兼容加密', '厂商内置工具']) {
          expect(encoded, isNot(contains(text)));
        }
        expect(original.reasoning, '不可迁移推理');
        expect(convertLlmHistory(converted, target), converted);
      });
    }
  }
  test('同目标保留原生签名，单独更换模型或端点也触发转换', () {
    const target = LlmRequestTarget(
      protocol: LlmApiProtocol.anthropic,
      endpoint: 'https://example.com/v1/messages',
      apiKey: '',
      model: 'model',
    );
    final turn = LlmAssistantTurn(
      text: '答复',
      reasoning: '摘要',
      replay: LlmReplayEnvelope(
        protocol: target.protocol,
        endpoint: Uri.parse(target.endpoint),
        model: target.model,
        items: [
          {'type': 'thinking', 'thinking': '摘要', 'signature': '原签名'},
          {'type': 'text', 'text': '答复'},
        ],
      ),
    );
    expect(identical(convertLlmHistory([turn], target).single, turn), isTrue);
    for (final changed in [
      const LlmRequestTarget(
        protocol: LlmApiProtocol.anthropic,
        endpoint: 'https://example.com/v1/messages',
        apiKey: '',
        model: 'other',
      ),
      const LlmRequestTarget(
        protocol: LlmApiProtocol.anthropic,
        endpoint: 'https://other.example/v1/messages',
        apiKey: '',
        model: 'model',
      ),
    ]) {
      final converted =
          convertLlmHistory([turn], changed).single as LlmAssistantTurn;
      expect(converted.reasoning, isEmpty);
      expect(jsonEncode(converted.replay.items), isNot(contains('signature')));
    }
  });
}
