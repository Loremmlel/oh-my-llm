import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/favorites/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/workspace/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../../../helpers/chat/controllable_chat_conversation_repository.dart';
import '../../../../helpers/chat/fake_chat_generation_client.dart';
import '../../../../helpers/fixtures.dart';

/// 可记录定向查询次数的空收藏 facade。
class _CountingFavoritesFacade implements ChatFavoritesFacade {
  int snapshotCallCount = 0;

  @override
  int get revision => 0;

  @override
  ChatFavoritesSnapshot snapshotFor(Set<String> assistantContents) {
    snapshotCallCount += 1;
    return const ChatFavoritesSnapshot(
      entries: [],
      collections: [],
      defaultCollectionId: 'sys',
    );
  }

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
    apiProtocol: LlmApiProtocol.chatCompletions,
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

  group('ChatWorkspaceComposerState.compose', () {
    ChatWorkspaceComposerReadModel composerReadModel({
      TemplatePrompt? selectedTemplatePrompt,
      double? cacheHitRate,
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
        cacheHitRate: cacheHitRate,
      );
    }

    test('非编辑态使用 read-model 的 normal selection', () {
      final template = TestFixtures.templatePrompt(id: 'tp-1');
      final state = ChatWorkspaceComposerState.compose(
        readModel: composerReadModel(
          selectedTemplatePrompt: template,
          cacheHitRate: 0.375,
        ),
        editingDraft: ComposerDraft.empty,
        isEditingMessage: false,
        templatePrompts: [template],
      );
      expect(state.selectedTemplatePrompt, same(template));
      expect(state.isEditingMessage, isFalse);
      expect(state.cacheHitRate, 0.375);
    });

    test('编辑态用 editingDraft 的选择覆盖；无模板编辑不回落 normal selection', () {
      final normalTemplate = TestFixtures.templatePrompt(id: 'tp-normal');
      final editingTemplate = TestFixtures.templatePrompt(id: 'tp-edit');
      final editingDraft = ComposerDraft(
        selectedTemplatePromptId: editingTemplate.id,
      );
      final sourceReadModel = composerReadModel(
        selectedTemplatePrompt: normalTemplate,
      );
      final state = ChatWorkspaceComposerState.compose(
        readModel: sourceReadModel,
        editingDraft: editingDraft,
        isEditingMessage: true,
        templatePrompts: [normalTemplate, editingTemplate],
      );
      expect(state.selectedTemplatePrompt, same(editingTemplate));
      expect(state.isEditingMessage, isTrue);

      // 编辑无模板消息：effective 为 null，不回落会话级 normal selection。
      final noTemplateEdit = ChatWorkspaceComposerState.compose(
        readModel: sourceReadModel,
        editingDraft: ComposerDraft.empty,
        isEditingMessage: true,
        templatePrompts: [normalTemplate],
      );
      expect(noTemplateEdit.selectedTemplatePrompt, isNull);
    });

    test('编辑选择指向已删除模板时解析为 null', () {
      final state = ChatWorkspaceComposerState.compose(
        readModel: composerReadModel(),
        editingDraft: const ComposerDraft(selectedTemplatePromptId: 'tp-gone'),
        isEditingMessage: true,
        templatePrompts: const [],
      );
      expect(state.selectedTemplatePrompt, isNull);
    });
  });

  group('workspace 拆分 provider', () {
    late AppDatabase database;
    late ControllableChatConversationRepository repository;
    late FakeChatGenerationClient fakeClient;
    late _CountingFavoritesFacade favoritesFacade;
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
      repository = ControllableChatConversationRepository(database);
      fakeClient = FakeChatGenerationClient();
      favoritesFacade = _CountingFavoritesFacade();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          chatGenerationClientProvider.overrideWithValue(fakeClient),
          chatConversationRepositoryProvider.overrideWithValue(repository),
          // 消息状态依赖收藏 facade 快照，组合层未挂载时默认实现抛
          // StateError，此处注入空快照。
          chatFavoritesFacadeProvider.overrideWithValue(favoritesFacade),
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

        final composer = container.read(chatWorkspaceComposerReadModelProvider);
        expect(composer.reasoningEnabled, isFalse);
        expect(composer.supportsReasoning, isFalse);
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

      final messages = container.read(chatWorkspaceMessagesStateProvider);
      final composer = container.read(chatWorkspaceComposerReadModelProvider);
      expect(
        messages.userMessages.every((m) => m.role == ChatMessageRole.user),
        isTrue,
      );
      // excluded count 与 conversation.isMessageExcluded 按可见消息一致。
      final conversation = messages.conversation;
      final expectedExcluded = messages.messages
          .where((m) => conversation.isMessageExcluded(m.id))
          .length;
      expect(composer.excludedMessageCount, expectedExcluded);
      // 排除动作确实生效：计数随真实排除从 0 变为正数。
      expect(composer.excludedMessageCount, greaterThan(0));
    });

    test('拆分状态中的集合不可外部修改', () {
      final messages = container.read(chatWorkspaceMessagesStateProvider);
      final composer = container.read(chatWorkspaceComposerReadModelProvider);
      expect(
        () => messages.messages.add(TestFixtures.userMessage(id: 'add-try')),
        throwsUnsupportedError,
      );
      expect(
        () => messages.favoritedAssistantContents.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => composer.templatePrompts.add(
          TestFixtures.templatePrompt(id: 'add-try'),
        ),
        throwsUnsupportedError,
      );
    });

    test('五十万字长会话流式更新只通知消息状态且不重复查询收藏', () async {
      final longText = List.filled(4200, '字').join();
      final nodes = <ChatMessage>[];
      String? parentId;
      for (var index = 0; index < 120; index += 1) {
        final message = ChatMessage(
          id: 'history-$index',
          role: index.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
          content: longText,
          createdAt: DateTime(2026, 1, 1).add(Duration(seconds: index)),
          parentId: parentId,
        );
        nodes.add(message);
        parentId = message.id;
      }
      await repository.saveConversation(
        ChatConversation(
          id: 'long-conversation',
          messageNodes: nodes,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 2),
        ),
      );

      final controlled = fakeClient.enqueueControlledStream();
      addTearDown(controlled.close);
      var composerNotifications = 0;
      var messageNotifications = 0;
      final composerSubscription = container.listen(
        chatWorkspaceComposerReadModelProvider,
        (_, _) => composerNotifications += 1,
      );
      final messageSubscription = container.listen(
        chatWorkspaceMessagesStateProvider,
        (_, _) => messageNotifications += 1,
      );
      addTearDown(composerSubscription.close);
      addTearDown(messageSubscription.close);

      final send = container
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '新的问题',
            modelConfig: container.read(llmModelConfigsProvider).first,
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      await controlled.listened;
      final messagesBeforeChunks = container.read(
        chatWorkspaceMessagesStateProvider,
      );
      composerNotifications = 0;
      messageNotifications = 0;
      final favoriteCallsBeforeChunks = favoritesFacade.snapshotCallCount;

      for (final delta in ['第一段', '第二段', '第三段']) {
        controlled.add(ChatGenerationChunk(contentDelta: delta));
        await Future<void>.value();
      }

      final messages = container.read(chatWorkspaceMessagesStateProvider);
      expect(messages.messages.last.content, '第一段第二段第三段');
      expect(
        identical(messages.userMessages, messagesBeforeChunks.userMessages),
        isTrue,
      );
      expect(
        identical(
          messages.structureConversation,
          messagesBeforeChunks.structureConversation,
        ),
        isTrue,
      );
      expect(messageNotifications, greaterThan(0));
      expect(messageNotifications, lessThanOrEqualTo(3));
      expect(composerNotifications, 0);
      expect(favoritesFacade.snapshotCallCount, favoriteCallsBeforeChunks);

      await controlled.close();
      await send;
    });
  });
}
