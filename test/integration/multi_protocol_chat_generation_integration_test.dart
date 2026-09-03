import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../helpers/integration_test_helpers.dart';

const _historicalContent = '可回放的历史正文';
const _historicalReasoning = '不得回放的历史思考';
const _finalContent = '正文';
const _finalReasoning = '思考';
const _systemPrompt = '你是集成测试助手';

void main() {
  for (final protocol in const [LlmApiProtocol.chatCompletions]) {
    test('${protocol.name} 真实链路产生并持久化一致的中立回复', () async {
      final harness = await _createHarness(protocol: protocol);
      addTearDown(harness.dispose);

      await _send(harness.container, protocol);

      final state = harness.container.read(chatSessionsProvider);
      final assistant = state.activeConversation.messages.last;
      expect(assistant.role, ChatMessageRole.assistant);
      expect(assistant.content, _finalContent);
      expect(assistant.reasoningContent, _finalReasoning);
      expect(assistant.finishReason, 'stop');
      expect(state.isStreaming, isFalse);

      final persisted = SqliteChatConversationRepository(harness.database)
          .loadConversation('conversation-1');
      expect(persisted, isNotNull);
      expect(persisted!.messages.last.content, _finalContent);
      expect(persisted.messages.last.reasoningContent, _finalReasoning);
      expect(persisted.messages.last.finishReason, 'stop');

      final request = harness.httpClient.requests.single;
      _expectProtocolRequest(request, protocol);
      final body = (request as http.Request).body;
      expect(body, contains(_historicalContent));
      expect(body, isNot(contains(_historicalReasoning)));
    });

    test('${protocol.name} 原生错误保留部分回复并走 durable inline 失败', () async {
      final harness = await _createHarness(protocol: protocol, fail: true);
      addTearDown(harness.dispose);

      await _send(harness.container, protocol);

      final state = harness.container.read(chatSessionsProvider);
      final assistant = state.activeConversation.messages.last;
      expect(assistant.role, ChatMessageRole.assistant);
      expect(assistant.content, '部分回复');
      expect(state.errorMessage, contains('协议测试错误'));
      expect(state.errorMessageAssistantId, assistant.id);
      expect(state.isStreaming, isFalse);

      final persisted = SqliteChatConversationRepository(harness.database)
          .loadConversation('conversation-1');
      expect(persisted, isNotNull);
      expect(persisted!.messages.last.id, assistant.id);
      expect(persisted.messages.last.content, '部分回复');
    });
  }
}

Future<_Harness> _createHarness({
  required LlmApiProtocol protocol,
  bool fail = false,
}) async {
  final database = AppDatabase.inMemory();
  final preferences = await createSeededPreferences();
  final repository = SqliteChatConversationRepository(database);
  await repository.saveConversation(_seedConversation());

  final httpClient = _ProtocolStreamingHttpClient(
    protocol: protocol,
    fail: fail,
  );
  final transport = LlmHttpStreamTransport(httpClient: httpClient);
  final router = ProtocolRoutingChatGenerationClient(
    chatCompletions: ChatCompletionsClient(transport: transport),
    responses: ResponsesClient(transport: transport),
    anthropic: AnthropicMessagesClient(transport: transport),
  );
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      chatConversationRepositoryProvider.overrideWithValue(repository),
      chatGenerationClientProvider.overrideWithValue(router),
    ],
  );
  // 触发 controller build，确保种子会话在 generation 前已加载。
  expect(
    container.read(chatSessionsProvider).activeConversation.id,
    'conversation-1',
  );
  return _Harness(
    database: database,
    container: container,
    httpClient: httpClient,
  );
}

Future<void> _send(ProviderContainer container, LlmApiProtocol protocol) {
  return container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: '新问题',
        modelConfig: LlmModelConfig(
          id: 'model-${protocol.name}',
          displayName: protocol.displayName,
          apiUrl: 'https://api.example.com',
          apiKey: 'protocol-key',
          modelName: 'test-model',
          supportsReasoning: true,
          apiProtocol: protocol,
        ),
        presetPrompt: PresetPrompt(
          id: 'integration-system-prompt',
          name: '集成测试 System',
          messages: const [
            PromptMessage(
              id: 'integration-system-message',
              role: PromptMessageRole.system,
              content: _systemPrompt,
            ),
          ],
          updatedAt: DateTime(2026, 8, 9),
        ),
        reasoningEnabled: true,
        reasoningEffort: ReasoningEffort.medium,
      );
}

ChatConversation _seedConversation() {
  final createdAt = DateTime(2026, 8, 9, 10);
  return ChatConversation(
    id: 'conversation-1',
    createdAt: createdAt,
    updatedAt: createdAt,
    messageNodes: [
      ChatMessage(
        id: 'historical-user',
        role: ChatMessageRole.user,
        content: '历史问题',
        createdAt: createdAt,
      ),
      ChatMessage(
        id: 'historical-assistant',
        parentId: 'historical-user',
        role: ChatMessageRole.assistant,
        content: _historicalContent,
        reasoningContent: _historicalReasoning,
        createdAt: createdAt.add(const Duration(seconds: 1)),
      ),
    ],
    selectedChildByParentId: const {
      rootConversationParentId: 'historical-user',
      'historical-user': 'historical-assistant',
    },
  );
}

void _expectProtocolRequest(http.BaseRequest request, LlmApiProtocol protocol) {
  final payload =
      jsonDecode((request as http.Request).body) as Map<String, dynamic>;
  switch (protocol) {
    case LlmApiProtocol.chatCompletions:
      expect(request.url.path, '/v1/chat/completions');
      expect(_header(request.headers, 'authorization'), 'Bearer protocol-key');
      expect(payload['reasoning_effort'], 'medium');
    case LlmApiProtocol.responses:
      expect(request.url.path, '/v1/responses');
      expect(_header(request.headers, 'authorization'), 'Bearer protocol-key');
      expect(payload['store'], isFalse);
      expect(payload.containsKey('previous_response_id'), isFalse);
      expect(payload.containsKey('conversation'), isFalse);
      expect(payload['reasoning'], {
        'effort': 'medium',
        'summary': 'auto',
        'context': 'current_turn',
      });
    case LlmApiProtocol.anthropic:
      expect(request.url.path, '/v1/messages');
      expect(_header(request.headers, 'x-api-key'), 'protocol-key');
      expect(_header(request.headers, 'anthropic-version'), '2023-06-01');
      expect(payload['cache_control'], {'type': 'ephemeral'});
      expect(payload['thinking'], {
        'type': 'adaptive',
        'display': 'summarized',
      });
      expect(payload['system'], _systemPrompt);
      final messages = (payload['messages'] as List).cast<Map>();
      expect(messages.map((message) => message['role']), [
        'user',
        'assistant',
        'user',
      ]);
      expect(messages.map((message) => message['content']), [
        '历史问题',
        _historicalContent,
        '新问题',
      ]);
  }
}

String? _header(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

final class _Harness {
  const _Harness({
    required this.database,
    required this.container,
    required this.httpClient,
  });

  final AppDatabase database;
  final ProviderContainer container;
  final _ProtocolStreamingHttpClient httpClient;

  void dispose() {
    container.dispose();
    database.close();
  }
}

final class _ProtocolStreamingHttpClient extends http.BaseClient {
  _ProtocolStreamingHttpClient({required this.protocol, required this.fail});

  final LlmApiProtocol protocol;
  final bool fail;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = fail ? _errorSse(protocol) : _successSse(protocol);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

String _successSse(LlmApiProtocol protocol) {
  return switch (protocol) {
    LlmApiProtocol.chatCompletions =>
      'data: {"choices":[{"delta":{"reasoning_content":"$_finalReasoning"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"$_finalContent"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
    LlmApiProtocol.responses =>
      'data: {"type":"response.reasoning_summary_text.delta","delta":"$_finalReasoning"}\n\n'
          'data: {"type":"response.output_text.delta","delta":"$_finalContent"}\n\n'
          'data: {"type":"response.completed","response":{}}\n\n',
    LlmApiProtocol.anthropic =>
      'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"$_finalReasoning"}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"$_finalContent"}}\n\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n'
          'data: {"type":"message_stop"}\n\n',
  };
}

String _errorSse(LlmApiProtocol protocol) {
  return switch (protocol) {
    LlmApiProtocol.chatCompletions =>
      'data: {"choices":[{"delta":{"content":"部分回复"}}]}\n\n'
          'data: {"error":{"message":"协议测试错误"}}\n\n',
    LlmApiProtocol.responses =>
      'data: {"type":"response.output_text.delta","delta":"部分回复"}\n\n'
          'data: {"type":"error","message":"协议测试错误","code":"test_error"}\n\n',
    LlmApiProtocol.anthropic =>
      'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"部分回复"}}\n\n'
          'data: {"type":"error","error":{"type":"test_error","message":"协议测试错误"}}\n\n',
  };
}
