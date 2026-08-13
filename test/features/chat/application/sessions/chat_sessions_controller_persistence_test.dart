import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

import '../../../../helpers/chat/flaky_chat_conversation_repository.dart';
import '../../../../helpers/chat/fake_chat_generation_client.dart';

/// 测试用模型配置，与 SharedPreferences 中的 id 一致。
final _testModel = LlmModelConfig(
  id: 'model-1',
  displayName: 'Test Model',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test',
  modelName: 'test-model',
  supportsReasoning: false,
);

void main() {
  late AppDatabase database;
  late FlakyChatConversationRepository repository;
  late FakeChatGenerationClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
        items: const [
          LlmProviderConfig(
            id: 'provider-1',
            name: 'Test Provider',
            apiUrl: 'https://api.example.com/v1/chat/completions',
            apiKey: 'sk-test',
            apiProtocol: LlmApiProtocol.chatCompletions,
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'Test Model',
                modelName: 'test-model',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        toJson: (provider) => provider.toJson(),
      ),
    });
    database = AppDatabase.inMemory();
    repository = FlakyChatConversationRepository(database);
    fakeClient = FakeChatGenerationClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        chatGenerationClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() {
      container.dispose();
      database.close();
    });
  });

  Future<void> sendMsg(String content, {Duration? retryDelay}) => container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: content,
        modelConfig: _testModel,
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
        retryDelay: retryDelay,
      );

  // ── retry 中间 save 失败 ──────────────────────────────────────────────────

  test('retry 中间 save 失败时终止重试、不发出下一请求', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    // updateActiveConversationPreferences 自身触发一次 fire-and-forget save，
    // 重置计数后让第 1 次=pending save（成功）、第 2 次=attempt1 空->中间 save（失败）。
    repository.saveConversationCallCount = 0;
    repository.failOnSaveCallIndex = 2;
    fakeClient.enqueueChunks(['']); // 第 1 次空回复
    fakeClient.enqueueChunks(['成功']); // 不应被消费

    await sendMsg('测试重试中间持久化失败', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(fakeClient.requestHistory.length, 1); // 重试被终止，未发出第 2 次请求
    expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
    expect(state.isStreaming, isFalse);
    expect(state.isAutoRetryWaiting, isFalse);
  });
}
