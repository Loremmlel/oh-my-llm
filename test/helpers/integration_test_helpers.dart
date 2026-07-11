import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';

/// 集成测试共享夹具：测试用模型配置。
///
/// id 需与 SharedPreferences 种子数据中的模型 id 一致。
final testModel = LlmModelConfig(
  id: 'model-1',
  displayName: 'Test Model',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test',
  modelName: 'test-model',
  supportsReasoning: false,
);

/// 集成测试共享夹具：测试用记忆提示词。
final testMemoryPrompt = MemoryPrompt(
  id: 'memory-1',
  name: '研发总结',
  content: '请总结当前对话中的关键事实、约束与待办。',
  updatedAt: DateTime(2026, 5, 1),
);

/// 创建带有模型配置种子数据的 SharedPreferences 实例。
Future<SharedPreferences> createSeededPreferences() async {
  SharedPreferences.setMockInitialValues({
    llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
      items: const [
        LlmProviderConfig(
          id: 'provider-1',
          name: 'Test Provider',
          apiUrl: 'https://api.example.com/v1/chat/completions',
          apiKey: 'sk-test',
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
  return SharedPreferences.getInstance();
}

/// 向指定 container 的活动会话发送一条消息并等待流式回复完成。
Future<void> sendMsg(
  ProviderContainer container, {
  required String content,
  LlmModelConfig? modelConfig,
}) =>
    container.read(chatSessionsProvider.notifier).sendMessage(
          content: content,
          modelConfig: modelConfig ?? testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

/// 创建带有标准集成测试 override 的 ProviderContainer。
ProviderContainer createTestContainer({
  required AppDatabase database,
  required SharedPreferences preferences,
  required ChatCompletionClient fakeClient,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      chatCompletionClientProvider.overrideWithValue(fakeClient),
    ],
  );
}
