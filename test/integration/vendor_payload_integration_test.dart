/// 厂商 URL -> 适配器 -> HTTP 请求体集成测试。
///
/// 验证从 LlmModelConfig.apiUrl 主机名到 HTTP 请求体包含正确厂商字段的完整链路。
/// 现有 openai_compatible_chat_client_test.dart 已覆盖 OpenAI 官方主机和
/// Google 主机，本文件补充 DeepSeek/Ark 主机的 thinking 字段验证。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  test('DeepSeek 主机 + reasoningEffort=medium -> thinking=enabled 且 reasoning_effort=medium', () async {
    Map<String, dynamic>? capturedPayload;

    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeHttpClient((request) async {
        capturedPayload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
          200,
        );
      }),
    );

    await client.streamCompletion(
      modelConfig: _modelConfig(
        apiUrl: 'https://api.deepseek.com/v1/chat/completions',
      ),
      messages: const [
        ChatCompletionRequestMessage(
          role: ChatMessageRole.user,
          content: '你好',
        ),
      ],
      reasoningEffort: ReasoningEffort.medium,
    ).drain<void>();

    expect(capturedPayload, isNotNull);
    expect(capturedPayload!['thinking'], {'type': 'enabled'});
    expect(capturedPayload!['reasoning_effort'], 'medium');
    expect(capturedPayload!.containsKey('extra_body'), isFalse);
  });

  test('DeepSeek 主机 + reasoningEffort=null -> thinking=disabled 且无 reasoning_effort', () async {
    Map<String, dynamic>? capturedPayload;

    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeHttpClient((request) async {
        capturedPayload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
          200,
        );
      }),
    );

    await client.streamCompletion(
      modelConfig: _modelConfig(
        apiUrl: 'https://api.deepseek.com/v1/chat/completions',
      ),
      messages: const [
        ChatCompletionRequestMessage(
          role: ChatMessageRole.user,
          content: '你好',
        ),
      ],
    ).drain<void>();

    expect(capturedPayload, isNotNull);
    expect(capturedPayload!['thinking'], {'type': 'disabled'});
    expect(capturedPayload!.containsKey('reasoning_effort'), isFalse);
  });

  test('Ark 主机 + reasoningEffort=high -> thinking=enabled 且 reasoning_effort=high', () async {
    Map<String, dynamic>? capturedPayload;

    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeHttpClient((request) async {
        capturedPayload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
          200,
        );
      }),
    );

    await client.streamCompletion(
      modelConfig: _modelConfig(
        apiUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      ),
      messages: const [
        ChatCompletionRequestMessage(
          role: ChatMessageRole.user,
          content: '你好',
        ),
      ],
      reasoningEffort: ReasoningEffort.high,
    ).drain<void>();

    expect(capturedPayload, isNotNull);
    expect(capturedPayload!['thinking'], {'type': 'enabled'});
    expect(capturedPayload!['reasoning_effort'], 'high');
  });

  test('默认兼容主机 + reasoningEffort=low -> 无 thinking 无 extra_body，有 reasoning_effort', () async {
    Map<String, dynamic>? capturedPayload;

    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeHttpClient((request) async {
        capturedPayload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
          200,
        );
      }),
    );

    await client.streamCompletion(
      modelConfig: _modelConfig(
        apiUrl: 'https://api.example.com/v1/chat/completions',
      ),
      messages: const [
        ChatCompletionRequestMessage(
          role: ChatMessageRole.user,
          content: '你好',
        ),
      ],
      reasoningEffort: ReasoningEffort.low,
    ).drain<void>();

    expect(capturedPayload, isNotNull);
    expect(capturedPayload!.containsKey('thinking'), isFalse);
    expect(capturedPayload!.containsKey('extra_body'), isFalse);
    expect(capturedPayload!['reasoning_effort'], 'low');
  });
}

LlmModelConfig _modelConfig({
  String apiUrl = 'https://api.example.com/v1/chat/completions',
}) =>
    LlmModelConfig(
      id: 'model-1',
      displayName: 'Test Model',
      apiUrl: apiUrl,
      apiKey: 'sk-test',
      modelName: 'test-model',
      supportsReasoning: true,
    );

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
