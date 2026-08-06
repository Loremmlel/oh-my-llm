import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_composer_command.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

import '../../../helpers/controllable_chat_conversation_repository.dart';
import '../../../helpers/fake_chat_completion_client.dart';

/// 标记「未显式传模型」的哨兵，区分「不传默认解析」与「显式传 null（无模型）」。
const _useDefaultModel = Object();

/// ChatComposerCommand 的编排契约：dispatch 的校验/拼接/提交语义与 toolbar
/// 命名的编排方法。容器用与 widget 测试一致的 overrides 驱动真实会话。
void main() {
  late AppDatabase database;
  late ControllableChatConversationRepository repository;
  late FakeChatCompletionClient fakeClient;
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
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'Test Model',
                modelName: 'test-model',
                supportsReasoning: false,
              ),
            ],
          ),
          LlmProviderConfig(
            id: 'provider-empty',
            name: 'Empty Provider',
            apiUrl: 'https://empty.example.com/v1/chat/completions',
            apiKey: 'sk-empty',
            models: [],
          ),
          LlmProviderConfig(
            id: 'provider-2',
            name: 'Second Provider',
            apiUrl: 'https://api2.example.com/v1/chat/completions',
            apiKey: 'sk-2',
            models: [
              LlmProviderModelConfig(
                id: 'model-2',
                displayName: 'Second Model',
                modelName: 'test-model-2',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        toJson: (provider) => provider.toJson(),
      ),
    });
    database = AppDatabase.inMemory();
    repository = ControllableChatConversationRepository(database);
    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    database.close();
  });

  LlmModelConfig model() => container.read(llmModelConfigsProvider).first;

  ChatComposerSubmitIntent intentFor(
    String body, {
    String? editingMessageId,
    String? conversationId,
    Object? selectedModel = _useDefaultModel,
  }) {
    return ChatComposerSubmitIntent(
      conversationId:
          conversationId ?? container.read(activeConversationIdProvider),
      body: body,
      selectedModel: identical(selectedModel, _useDefaultModel)
          ? model()
          : selectedModel as LlmModelConfig?,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
      editingMessageId: editingMessageId,
    );
  }

  test('normal accepted 返回 completion，draft body 清空、selection 保留', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '你好');
    fakeClient.enqueueChunks(['回复']);

    final result = command.dispatch(intentFor('你好'));
    expect(result, isA<ChatComposerAccepted>());
    final accepted = result as ChatComposerAccepted;
    expect(accepted.wasEdit, isFalse);
    // accepted 同步清空 draft body，不等待 completion。
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '',
    );
    await accepted.completion;
    expect(fakeClient.requestHistory, hasLength(1));
  });

  test('空 body / 无模型 / stale 返回 typed rejected，draft 与请求不变', () {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '保留');

    // 空 body（trim 后为空）。
    final emptyResult = command.dispatch(intentFor('   '));
    expect(emptyResult, isA<ChatComposerRejected>());
    expect(
      (emptyResult as ChatComposerRejected).reason,
      ChatComposerRejectReason.empty,
    );

    // 无模型。
    final noModelResult = command.dispatch(
      intentFor('abc', selectedModel: null),
    );
    expect(noModelResult, isA<ChatComposerRejected>());
    expect(
      (noModelResult as ChatComposerRejected).reason,
      ChatComposerRejectReason.noModel,
    );

    // stale：conversationId 与活动会话不一致。
    final staleResult = command.dispatch(
      intentFor('abc', conversationId: 'other'),
    );
    expect(staleResult, isA<ChatComposerRejected>());
    expect(
      (staleResult as ChatComposerRejected).reason,
      ChatComposerRejectReason.staleConversation,
    );

    expect(fakeClient.requestHistory, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '保留',
    );
  });

  test('busy 返回 rejected，draft 与请求不变', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '保留');

    // 用 pending save gate 让一次 sendMessage 停在 preparing，期间 busy。
    repository.gateSave(1);
    fakeClient.enqueueChunks(['占位占位占位占位']);
    final sendFuture = container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '占位占位占位占位',
          modelConfig: model(),
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    await repository.awaitReached(1);

    expect(container.read(isChatBusyProvider), isTrue);
    final result = command.dispatch(intentFor('你好'));
    expect(result, isA<ChatComposerRejected>());
    expect(
      (result as ChatComposerRejected).reason,
      ChatComposerRejectReason.busy,
    );
    expect(fakeClient.requestHistory, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '保留',
    );

    repository.releaseSave(1);
    await sendFuture;
  });

  test('edit accepted 走 editMessage 分支，draft body 提交后清空', () async {
    fakeClient.enqueueChunks(['原始回复']);
    await container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '原始消息',
          modelConfig: model(),
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    final conversation = container.read(activeChatConversationProvider);
    final userMessage = conversation.messages.firstWhere(
      (m) => m.role == ChatMessageRole.user,
    );

    final command = container.read(chatComposerCommandProvider);
    fakeClient.enqueueChunks(['编辑后回复']);
    final result = command.dispatch(
      intentFor('编辑后内容', editingMessageId: userMessage.id),
    );
    expect(result, isA<ChatComposerAccepted>());
    final accepted = result as ChatComposerAccepted;
    expect(accepted.wasEdit, isTrue);
    await accepted.completion;

    // 编辑产生新分支，不额外追加普通 user 路径（原始 + 编辑再生成 = 2 次请求）。
    expect(fakeClient.requestHistory, hasLength(2));
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversation.id)
          .body,
      '',
    );
    final editedConversation = container.read(activeChatConversationProvider);
    expect(
      editedConversation.messages.any((m) => m.content == '编辑后内容'),
      isTrue,
    );
  });

  test('selectProvider 无模型 no-op、有模型选 first；selectPreset 不写 draft/default', () {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);

    // 无有效模型的 provider → no-op，保持既有选择不变。
    final initialModelId = container
        .read(activeChatConversationProvider)
        .selectedModelId;
    command.selectProvider('provider-empty');
    expect(
      container.read(activeChatConversationProvider).selectedModelId,
      initialModelId,
    );

    // 有模型的 provider → 选其第一个模型，并记住为默认。
    command.selectProvider('provider-2');
    expect(
      container.read(activeChatConversationProvider).selectedModelId,
      'model-2',
    );
    expect(container.read(chatDefaultsProvider).defaultModelId, 'model-2');

    // selectPreset 只写 conversation 持久字段。
    command.selectPreset('prompt-x');
    expect(
      container.read(activeChatConversationProvider).selectedPresetPromptId,
      'prompt-x',
    );
    command.selectPreset(null);
    expect(
      container.read(activeChatConversationProvider).selectedPresetPromptId,
      noPresetPromptSelectedId,
    );
    // 不触碰模板选择与 chatDefaults 的 preset 记忆。
    expect(
      container.read(composerTemplateSelectionProvider(conversationId)),
      isNull,
    );
    expect(container.read(chatDefaultsProvider).defaultPresetPromptId, isNull);
  });

  test('createConversationAndResetDraft 清 active draft', () async {
    final command = container.read(chatComposerCommandProvider);
    final convId = container.read(activeConversationIdProvider);
    container.read(composerDraftProvider.notifier).setBody(convId, '草稿');

    // 空会话：不新建第二个 conversation，但清空当前 active draft。
    await command.createConversationAndResetDraft();
    expect(container.read(activeConversationIdProvider), convId);
    expect(
      container.read(composerDraftProvider.notifier).draftFor(convId).body,
      '',
    );
  });
}
