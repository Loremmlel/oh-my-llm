import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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
import 'package:oh_my_llm/features/settings/data/preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

import '../../../../helpers/fake_chat_completion_client.dart';

/// 测试用模型配置，与 SharedPreferences 中的 id 一致，确保 _resolveModelConfig 能找到它。
final testModel = LlmModelConfig(
  id: 'model-1',
  displayName: 'Test Model',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test',
  modelName: 'test-model',
  supportsReasoning: false,
);

final memoryPrompt = MemoryPrompt(
  id: 'memory-1',
  name: '研发总结',
  content: '请总结当前对话中的关键事实、约束与待办。',
  updatedAt: DateTime(2026, 5, 1),
);

/// Controller 测试统一装具。
///
/// 封装内存数据库、SharedPreferences、Fake 客户端与 ProviderContainer 的创建与
/// 清理，以及 [sendMsg] / [realIdleTimeoutStream] 等共享 helper。每个测试在 setUp
/// 中 [init] 独立实例，tearDown 调 [dispose] 释放资源。
class ControllerTestHarness {
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  Future<void> init() async {
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
    database = AppDatabase.inMemory();
    // 通过 Repository API 将预设提示词写入 SQLite
    await presetPromptRepository.saveAll(database, [
      PresetPrompt(
        id: 'prompt-1',
        name: '模板一',
        messages: const [
          PromptMessage(
            id: 'prompt-1-message-1',
            role: PromptMessageRole.user,
            content: '模板一前置',
            placement: PromptMessagePlacement.before,
          ),
        ],
        updatedAt: DateTime(2026, 4, 30),
      ),
      PresetPrompt(
        id: 'prompt-2',
        name: '模板二',
        messages: const [
          PromptMessage(
            id: 'prompt-2-message-1',
            role: PromptMessageRole.user,
            content: '模板二前置',
            placement: PromptMessagePlacement.before,
          ),
        ],
        updatedAt: DateTime(2026, 4, 30, 0, 1),
      ),
    ]);
    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
  }

  void dispose() {
    container.dispose();
    database.close();
  }

  /// 向活动会话发送一条消息并等待流式回复完成。
  Future<void> sendMsg(String content, {Duration? retryDelay}) => container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: content,
        modelConfig: testModel,
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
        retryDelay: retryDelay,
      );

  /// 用真实 [OpenAiCompatibleChatClient] 构造一条会触发 SSE idle 超时的流，
  /// 保留 async* 生成器对 error/done 事件的真实调度时序。
  ///
  /// mock HTTP 返回的 SSE 流先发一条 data 行（部分内容）后永不结束，配合短
  /// [idleTimeout] 触发 `_applySseIdleTimeout` 的 fireTimeout：在同一同步栈内对
  /// async StreamController 连续 addError + close。error 与 done 经 streamCompletion
  /// 的 async* 生成器投递，时序与生产环境一致。手工构造的 StreamController 或
  /// `Stream.error` 复现不出此 bug：事件不经 async* 生成器调度。
  Stream<ChatCompletionChunk> realIdleTimeoutStream({
    Duration idleTimeout = const Duration(milliseconds: 50),
  }) {
    final httpClient = _IdleTimeoutHttpClient();
    final client = OpenAiCompatibleChatClient(httpClient: httpClient);
    return client.streamCompletion(
      modelConfig: testModel,
      messages: const [
        ChatCompletionRequestMessage(role: ChatMessageRole.user, content: 'hi'),
      ],
      streamIdleTimeout: idleTimeout,
    );
  }
}

/// 返回一条先发一条 data 行后永不结束的 SSE 流，用于触发 idle 超时。
///
/// 配合 [OpenAiCompatibleChatClient] 的短 `streamIdleTimeout`，模拟服务器
/// 发送部分内容后长时间无响应的场景，迫使 `_applySseIdleTimeout` 触发
/// fireTimeout（在同一同步栈内连续 addError + close）。
class _IdleTimeoutHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sseController = StreamController<List<int>>();
    sseController.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"部分内容"}}]}\n\n'),
    );
    // 故意不 close：永不结束，迫使 idle 超时触发 fireTimeout。
    return http.StreamedResponse(sseController.stream, 200);
  }
}
