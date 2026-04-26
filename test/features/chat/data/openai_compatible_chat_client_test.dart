import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  test('streamCompletion parses OpenAI-compatible SSE chunks', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer sk-test-12345678');
        final payload = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload['thinking'], {
          'type': 'enabled',
        });
        expect(payload['reasoning_effort'], 'high');

        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"第一段 "}}]}\n\n',
            ),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"第二段"}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
          reasoningEffort: ReasoningEffort.high,
        )
        .toList();

    expect(chunks, ['第一段 ', '第二段']);
  });

  test('streamCompletion explicitly disables thinking when reasoning is off', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        final payload = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload['thinking'], {
          'type': 'disabled',
        });
        expect(payload.containsKey('reasoning_effort'), isFalse);

        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
        )
        .drain<void>();
  });

  test('streamCompletion omits thinking for official OpenAI hosts', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        final payload = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload['reasoning_effort'], 'xhigh');

        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    await client
        .streamCompletion(
          modelConfig: _modelConfig(
            apiUrl: 'https://api.openai.com/v1/chat/completions',
          ),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
          reasoningEffort: ReasoningEffort.xhigh,
        )
        .drain<void>();
  });

  test('streamCompletion surfaces API errors from SSE payloads', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"error":{"message":"invalid api key"}}\n\n'),
          ]),
          200,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(
        isA<ChatCompletionException>().having(
          (error) => error.message,
          'message',
          'invalid api key',
        ),
      ),
    );
  });

  test('streamCompletion rejects invalid API URLs before sending', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        throw UnimplementedError('Should not send request for invalid URLs.');
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(apiUrl: 'not-a-valid-url'),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(isA<ChatCompletionException>()),
    );
  });
}

LlmModelConfig _modelConfig({
  String apiUrl = 'https://api.example.com/v1/chat/completions',
}) {
  return LlmModelConfig(
    id: 'model-1',
    displayName: 'GPT-4.1',
    apiUrl: apiUrl,
    apiKey: 'sk-test-12345678',
    modelName: 'gpt-4.1',
    supportsReasoning: true,
  );
}

class _FakeStreamingHttpClient extends http.BaseClient {
  _FakeStreamingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
