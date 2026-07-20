/// PresetPrompt 拼接进请求消息集成测试。
///
/// 验证从 PresetPrompt 种子数据到 ChatClient 实际收到消息列表的完整链路：
/// PresetPrompt -> ChatSessionsController.resolvePresetPrompt
/// -> buildRequestMessages -> ChatClient.streamCompletion 收到的消息。
///
/// 拼接顺序：before 模板消息 -> 对话消息 -> after 模板消息。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();

    final presetPrompt = PresetPrompt(
      id: 'preset-1',
      name: '测试预设',
      messages: const [
        PromptMessage(
          id: 'before-1',
          role: PromptMessageRole.system,
          content: '系统前置指令',
          placement: PromptMessagePlacement.before,
        ),
        PromptMessage(
          id: 'before-latest-input-1',
          role: PromptMessageRole.user,
          content: '最新输入前指令',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
        PromptMessage(
          id: 'after-1',
          role: PromptMessageRole.user,
          content: '系统后置指令',
          placement: PromptMessagePlacement.after,
        ),
      ],
      updatedAt: DateTime(2026, 7, 1),
    );
    await presetPromptRepository.saveAll(database, [presetPrompt]);

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
    preferences = await SharedPreferences.getInstance();

    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
  });

  // ── before + after 模板消息正确拼接到请求 ──────────────────────────────────────

  test('发送消息时 before/beforeLatestInput/after 模板消息按正确顺序拼入请求', () async {
    final preset = container
        .read(presetPromptsProvider)
        .firstWhere((p) => p.id == 'preset-1');

    fakeClient.enqueueChunks(['回复内容']);
    await container.read(chatSessionsProvider.notifier).sendMessage(
          content: '用户消息',
          modelConfig: testModel,
          presetPrompt: preset,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final messages = fakeClient.lastRequestMessages;
    expect(messages, isNotEmpty);

    // 第 1 条：before 模板消息（system）
    expect(messages[0].role, ChatMessageRole.system);
    expect(messages[0].content, '系统前置指令');

    // 第 2 条：用户消息
    expect(messages[1].role, ChatMessageRole.user);
    expect(messages[1].content, '用户消息');

    // 第 3 条：beforeLatestInput 模板消息（user）
    expect(messages[2].role, ChatMessageRole.user);
    expect(messages[2].content, '最新输入前指令');

    // 第 4 条：after 模板消息（user）
    expect(messages[3].role, ChatMessageRole.user);
    expect(messages[3].content, '系统后置指令');
  });

  // ── 无 PresetPrompt 时只有对话消息 ──────────────────────────────────────────

  test('未选择 PresetPrompt 时请求仅包含对话消息', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg(container, content: '纯消息');

    final messages = fakeClient.lastRequestMessages;
    expect(messages, hasLength(1));
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[0].content, '纯消息');
  });

  // ── 多轮对话中模板消息每次都拼接 ────────────────────────────────────────────

  test('多轮对话中 PresetPrompt 模板消息每轮都正确拼接', () async {
    final preset = container
        .read(presetPromptsProvider)
        .firstWhere((p) => p.id == 'preset-1');

    // 第一轮
    fakeClient.enqueueChunks(['第一轮回复']);
    await container.read(chatSessionsProvider.notifier).sendMessage(
          content: '第一轮问题',
          modelConfig: testModel,
          presetPrompt: preset,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final firstRequest = fakeClient.lastRequestMessages;
    expect(firstRequest.first.content, '系统前置指令');
    expect(firstRequest.first.role, ChatMessageRole.system);
    expect(firstRequest.last.content, '系统后置指令');

    // 第二轮
    fakeClient.enqueueChunks(['第二轮回复']);
    await container.read(chatSessionsProvider.notifier).sendMessage(
          content: '第二轮问题',
          modelConfig: testModel,
          presetPrompt: preset,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final secondRequest = fakeClient.lastRequestMessages;
    expect(secondRequest.first.content, '系统前置指令');
    expect(secondRequest.first.role, ChatMessageRole.system);
    expect(secondRequest.last.content, '系统后置指令');
    expect(secondRequest.any((m) => m.content == '第一轮问题'), isTrue);
    expect(secondRequest.any((m) => m.content == '第二轮问题'), isTrue);
  });
}
