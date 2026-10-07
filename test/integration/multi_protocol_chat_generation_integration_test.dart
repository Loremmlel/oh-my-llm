import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

import '../helpers/integration_test_helpers.dart';

const _historicalContent = '可回放的历史正文';
const _historicalReasoning = '不得回放的历史思考';
const _finalContent = '正文';
const _finalReasoning = '思考';
const _systemPrompt = '你是集成测试助手';

void main() {
  test('生产组合绑定发送聊天请求并持久化正文、推理与终态', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await _send(harness.container);

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
    _expectProtocolRequest(request);
    final body = (request as http.Request).body;
    expect(body, contains(_historicalContent));
    expect(body, isNot(contains(_historicalReasoning)));
  });

  test('生产组合绑定将原生错误转为内联失败并持久化部分回复', () async {
    final harness = await _createHarness(fail: true);
    addTearDown(harness.dispose);

    await _send(harness.container);

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

Future<_Harness> _createHarness({bool fail = false}) async {
  final database = AppDatabase.inMemory();
  final preferences = await createSeededPreferences();
  final repository = SqliteChatConversationRepository(database);
  await repository.saveConversation(_seedConversation());

  final httpClient = _ProtocolStreamingHttpClient(fail: fail);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      appNetworkLoggerProvider.overrideWithValue(const NoopNetworkLogger()),
      customHeadersMapProvider.overrideWith((ref) => const {}),
      httpClientProvider.overrideWith((ref) {
        final client = CustomHeadersHttpClient(httpClient, {});
        ref.onDispose(client.close);
        return client;
      }),
      ...appCompositionOverrides(
        useInMemorySyncSecureStore: true,
        hostPlatform: TargetPlatform.windows,
      ),
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

Future<void> _send(ProviderContainer container) {
  return container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: '新问题',
        modelConfig: LlmModelConfig(
          id: 'model-chat-completions',
          displayName: '测试模型',
          apiUrl: 'https://api.example.com',
          apiKey: 'protocol-key',
          modelName: 'test-model',
          supportsReasoning: true,
          apiProtocol: LlmApiProtocol.chatCompletions,
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

void _expectProtocolRequest(http.BaseRequest request) {
  final payload =
      jsonDecode((request as http.Request).body) as Map<String, dynamic>;
  expect(request.url.path, '/v1/chat/completions');
  expect(_header(request.headers, 'authorization'), 'Bearer protocol-key');
  expect(payload['reasoning_effort'], 'medium');
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
  _ProtocolStreamingHttpClient({required this.fail});
  final bool fail;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = fail ? _errorSse() : _successSse();
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

String _successSse() =>
    'data: {"choices":[{"delta":{"reasoning_content":"$_finalReasoning"}}]}\n\n'
    'data: {"choices":[{"delta":{"content":"$_finalContent"},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

String _errorSse() =>
    'data: {"choices":[{"delta":{"content":"部分回复"}}]}\n\n'
    'data: {"error":{"message":"协议测试错误"}}\n\n';
