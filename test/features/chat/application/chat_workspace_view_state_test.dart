import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import '../../../helpers/controllable_chat_conversation_repository.dart';
import '../../../helpers/fake_chat_completion_client.dart';
import '../../../helpers/fixtures.dart';

/// 最小必填字段的空白会话（TestFixtures 未提供 conversation 工厂）。
ChatConversation _conversation() {
  return ChatConversation(
    id: 'c1',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

/// 空收藏快照的 facade，替代生产组合层绑定（默认实现直接抛 StateError）。
class _EmptyFavoritesFacade implements ChatFavoritesFacade {
  @override
  ChatFavoritesSnapshot get snapshot =>
      const ChatFavoritesSnapshot(entries: [], collections: []);

  @override
  String createCollection(String name) => name;

  @override
  void add(ChatFavoriteDraft draft) {}

  @override
  void remove(String favoriteId) {}
}

/// 构造一个仅含指定模型 id 的最小服务商。
LlmProviderConfig _provider(String id, List<String> modelIds) {
  return LlmProviderConfig(
    id: id,
    name: id,
    apiUrl: 'https://$id.example.com/v1/chat/completions',
    apiKey: 'sk-test',
    models: [
      for (final modelId in modelIds)
        LlmProviderModelConfig(
          id: modelId,
          displayName: modelId,
          modelName: modelId,
          supportsReasoning: false,
        ),
    ],
  );
}

void main() {
  group('resolveSelectedModel', () {
    test('conversation selected 优先', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: 'model-claude',
        rememberedModelId: 'model-gpt',
      );
      expect(selected!.id, 'model-claude');
    });

    test('无 conversation 选中时回退 remembered default', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: 'model-claude',
      );
      expect(selected!.id, 'model-claude');
    });

    test('无 remembered 时回退首模型', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: null,
      );
      expect(selected!.id, 'model-gpt');
    });

    test('空列表返回 null', () {
      expect(
        resolveSelectedModel(
          modelConfigs: const [],
          selectedModelId: null,
          rememberedModelId: null,
        ),
        isNull,
      );
    });
  });

  group('resolveSelectedProviderId', () {
    test('无可用服务商返回 null', () {
      expect(
        resolveSelectedProviderId(
          providers: const [],
          selectedModel: TestFixtures.gpt41(),
        ),
        isNull,
      );
    });

    test('选中模型所属服务商优先', () {
      final providers = [
        _provider('provider-a', ['model-gpt']),
      ];
      expect(
        resolveSelectedProviderId(
          providers: providers,
          selectedModel: TestFixtures.model(
            id: 'model-gpt',
            providerId: 'provider-a',
          ),
        ),
        'provider-a',
      );
    });

    test('选中模型不在服务商列表时回退首服务商', () {
      final providers = [
        _provider('provider-a', ['other']),
      ];
      expect(
        resolveSelectedProviderId(
          providers: providers,
          selectedModel: TestFixtures.gpt41(),
        ),
        'provider-a',
      );
    });
  });

  group('resolveSelectedTemplatePrompt', () {
    test('null 选择返回 null', () {
      expect(
        resolveSelectedTemplatePrompt([
          TestFixtures.templatePrompt(id: 'tp-1'),
        ], null),
        isNull,
      );
    });

    test('命中返回对应模板', () {
      final result = resolveSelectedTemplatePrompt([
        TestFixtures.templatePrompt(id: 'tp-1'),
      ], 'tp-1');
      expect(result!.id, 'tp-1');
    });

    test('选择不存在时返回 null', () {
      expect(
        resolveSelectedTemplatePrompt([
          TestFixtures.templatePrompt(id: 'tp-1'),
        ], 'tp-missing'),
        isNull,
      );
    });
  });

  group('resolveSelectedPresetPrompt', () {
    test('null 选择返回 null', () {
      expect(resolveSelectedPresetPrompt(const [], null), isNull);
    });

    test('sentinel（noPresetPromptSelectedId）返回 null，即使存在同名预设', () {
      expect(
        resolveSelectedPresetPrompt([
          TestFixtures.presetPrompt(id: noPresetPromptSelectedId),
        ], noPresetPromptSelectedId),
        isNull,
      );
    });

    test('命中返回对应预设', () {
      final prompt = TestFixtures.presetPrompt(id: 'preset-1');
      expect(resolveSelectedPresetPrompt([prompt], prompt.id), same(prompt));
    });

    test('选择不存在时返回 null', () {
      expect(
        resolveSelectedPresetPrompt([
          TestFixtures.presetPrompt(id: 'preset-1'),
        ], 'preset-missing'),
        isNull,
      );
    });
  });

  group('ChatWorkspaceViewState.compose', () {
    ChatWorkspaceComposerReadModel composerReadModel({
      TemplatePrompt? selectedTemplatePrompt,
    }) {
      return ChatWorkspaceComposerReadModel(
        modelProviders: const [],
        modelConfigs: const [],
        selectedProviderId: null,
        selectedModel: null,
        templatePrompts: const [],
        selectedTemplatePrompt: selectedTemplatePrompt,
        fixedPromptSequences: const [],
        isComposerCollapsed: false,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
        supportsReasoning: false,
        autoRetryEnabled: false,
        isBusy: false,
        isStreaming: false,
        isAutoRetryWaiting: false,
        excludedMessageCount: 0,
      );
    }

    ChatWorkspaceReadModel readModel({TemplatePrompt? selectedTemplatePrompt}) {
      return ChatWorkspaceReadModel(
        messages: ChatWorkspaceMessagesState(
          conversation: _conversation(),
          messages: const [],
          userMessages: const [],
          hasModels: false,
          isBusy: false,
          errorMessage: null,
          errorMessageAssistantId: null,
          emptyReplyAssistantId: null,
          errorModelDisplayName: '模型',
          autoRetryCount: 0,
          favoritedAssistantContents: const {},
        ),
        composer: composerReadModel(
          selectedTemplatePrompt: selectedTemplatePrompt,
        ),
      );
    }

    test('非编辑态使用 read-model 的 normal selection', () {
      final template = TestFixtures.templatePrompt(id: 'tp-1');
      final viewState = ChatWorkspaceViewState.compose(
        readModel: readModel(selectedTemplatePrompt: template),
        editingDraft: ComposerDraft.empty,
        isEditingMessage: false,
        templatePrompts: [template],
      );
      expect(viewState.composer.selectedTemplatePrompt, same(template));
      expect(viewState.composer.isEditingMessage, isFalse);
    });

    test('编辑态用 editingDraft 的选择覆盖；无模板编辑不回落 normal selection', () {
      final normalTemplate = TestFixtures.templatePrompt(id: 'tp-normal');
      final editingTemplate = TestFixtures.templatePrompt(id: 'tp-edit');
      final editingDraft = ComposerDraft(
        selectedTemplatePromptId: editingTemplate.id,
      );
      final sourceReadModel = readModel(selectedTemplatePrompt: normalTemplate);
      final viewState = ChatWorkspaceViewState.compose(
        readModel: sourceReadModel,
        editingDraft: editingDraft,
        isEditingMessage: true,
        templatePrompts: [normalTemplate, editingTemplate],
      );
      expect(viewState.composer.selectedTemplatePrompt, same(editingTemplate));
      expect(viewState.composer.isEditingMessage, isTrue);
      // messages 原样透传 compose 入参的 read-model，不重建新实例。
      expect(viewState.messages, same(sourceReadModel.messages));

      // 编辑无模板消息：effective 为 null，不回落会话级 normal selection。
      final noTemplateEdit = ChatWorkspaceViewState.compose(
        readModel: sourceReadModel,
        editingDraft: ComposerDraft.empty,
        isEditingMessage: true,
        templatePrompts: [normalTemplate],
      );
      expect(noTemplateEdit.composer.selectedTemplatePrompt, isNull);
    });

    test('编辑选择指向已删除模板时解析为 null', () {
      final viewState = ChatWorkspaceViewState.compose(
        readModel: readModel(),
        editingDraft: const ComposerDraft(selectedTemplatePromptId: 'tp-gone'),
        isEditingMessage: true,
        templatePrompts: const [],
      );
      expect(viewState.composer.selectedTemplatePrompt, isNull);
    });
  });

  group('chatWorkspaceReadModelProvider', () {
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
          // read-model 依赖收藏 facade 快照，组合层未挂载时默认实现抛
          // StateError，此处注入空快照。
          chatFavoritesFacadeProvider.overrideWithValue(
            _EmptyFavoritesFacade(),
          ),
        ],
      );
    });
    tearDown(() {
      container.dispose();
      database.close();
    });

    test(
      '不支持 reasoning 的模型：effective enabled 为 false 且不改写 conversation flag',
      () async {
        // 打开 conversation 的 reasoningEnabled（即使模型不支持）。
        container
            .read(chatSessionsProvider.notifier)
            .updateActiveConversationPreferences(reasoningEnabled: true);

        final readModel = container.read(chatWorkspaceReadModelProvider);
        expect(readModel.composer.reasoningEnabled, isFalse);
        expect(readModel.composer.supportsReasoning, isFalse);
        expect(
          container.read(activeChatConversationProvider).reasoningEnabled,
          isTrue,
        );
      },
    );

    test('userMessages 只含 user；excluded count 按可见消息计', () async {
      fakeClient.enqueueChunks(['回复']);
      await container
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '问题',
            modelConfig: container.read(llmModelConfigsProvider).first,
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      final excludedMessageId = container
          .read(activeChatConversationProvider)
          .messages
          .first
          .id;
      await container
          .read(chatSessionsProvider.notifier)
          .setMessagesExcluded(messageIds: [excludedMessageId], excluded: true);

      final readModel = container.read(chatWorkspaceReadModelProvider);
      expect(
        readModel.messages.userMessages.every(
          (m) => m.role == ChatMessageRole.user,
        ),
        isTrue,
      );
      // excluded count 与 conversation.isMessageExcluded 按可见消息一致。
      final conversation = readModel.messages.conversation;
      final expectedExcluded = readModel.messages.messages
          .where((m) => conversation.isMessageExcluded(m.id))
          .length;
      expect(readModel.composer.excludedMessageCount, expectedExcluded);
      // 排除动作确实生效：计数随真实排除从 0 变为正数。
      expect(readModel.composer.excludedMessageCount, greaterThan(0));
    });

    test('read-model 的 messages / favoritedAssistantContents 不可外部修改', () {
      final readModel = container.read(chatWorkspaceReadModelProvider);
      expect(
        () => readModel.messages.messages.add(
          TestFixtures.userMessage(id: 'add-try'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => readModel.messages.favoritedAssistantContents.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => readModel.composer.templatePrompts.add(
          TestFixtures.templatePrompt(id: 'add-try'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
