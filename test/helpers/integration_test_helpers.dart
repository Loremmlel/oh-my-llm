import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';
import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';

import 'test_harness.dart';

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
  return SharedPreferences.getInstance();
}

/// 向指定 container 的活动会话发送一条消息并等待流式回复完成。
Future<void> sendMsg(
  ProviderContainer container, {
  required String content,
  LlmModelConfig? modelConfig,
}) => container
    .read(chatSessionsProvider.notifier)
    .sendMessage(
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
  required ChatGenerationClient fakeClient,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      // 固定通知 session：与 widget harness 同一约定，测试不读取随机状态。
      chatGenerationNotificationSessionIdProvider.overrideWithValue(
        testChatGenerationNotificationSessionId,
      ),
      // 排除 composition 的 completion 绑定（由 fakeClient 接管），
      // Riverpod 禁止同一容器内对同一 provider 重复 override。
      ...appCompositionOverrides(
        useInMemorySyncSecureStore: true,
        bindChatGenerationClient: false,
        // 集成测试默认绑定 no-op 平台件：无论宿主平台都不触达 MethodChannel。
        notificationPlatformBindingsFactory:
            createOtherPlatformChatGenerationNotificationBindings,
        appWindowFactory: () => NoopAppWindow(),
      ),
      chatGenerationClientProvider.overrideWithValue(fakeClient),
    ],
  );
}
