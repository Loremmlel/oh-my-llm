import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/composer/chat_composer_command.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/preferences/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../../../helpers/chat/controllable_chat_conversation_repository.dart';
import '../../../../helpers/chat/fake_chat_generation_client.dart';

/// 标记「未显式传模型」的哨兵，区分「不传默认解析」与「显式传 null（无模型）」。
const _useDefaultModel = Object();

/// ChatComposerCommand 的编排契约：dispatch 的校验/拼接/提交语义与 toolbar
/// 命名的编排方法。容器用与 widget 测试一致的 overrides 驱动真实会话。
void main() {
  late AppDatabase database;
  late ControllableChatConversationRepository repository;
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
          LlmProviderConfig(
            id: 'provider-empty',
            name: 'Empty Provider',
            apiUrl: 'https://empty.example.com/v1/chat/completions',
            apiKey: 'sk-empty',
            apiProtocol: LlmApiProtocol.chatCompletions,
            models: [],
          ),
          LlmProviderConfig(
            id: 'provider-2',
            name: 'Second Provider',
            apiUrl: 'https://api2.example.com/v1/chat/completions',
            apiKey: 'sk-2',
            apiProtocol: LlmApiProtocol.chatCompletions,
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
    TemplatePrompt? templatePrompt,
    Map<String, String> variableValues = const {},
  }) {
    return ChatComposerSubmitIntent(
      conversationId:
          conversationId ?? container.read(activeConversationIdProvider),
      body: body,
      templatePrompt: templatePrompt,
      variableValues: variableValues,
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
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-1');
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
    // selection 保留，不被 dispatch 消费。
    expect(
      container.read(composerTemplateSelectionProvider(conversationId)),
      'tp-1',
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

  test('templated dispatch：变量值随 intent 传入，draft 只清 body 保留模板选择', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    // 模板变量值由 intent 携带，dispatch 只读 intent，无需注册到 Provider。
    final template = TemplatePrompt(
      id: 'tp-1',
      title: '变量模板',
      content: '请按{{title}}输出。',
      variables: [TemplatePromptVariable(name: 'title', defaultValue: '默认标题')],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-1');
    fakeClient.enqueueChunks(['回复']);

    final result = command.dispatch(
      intentFor('正文', templatePrompt: template, variableValues: {'title': '甲'}),
    );
    expect(result, isA<ChatComposerAccepted>());
    final accepted = result as ChatComposerAccepted;
    await accepted.completion;

    final sent = fakeClient.requestHistory.single
        .map((m) => m.content)
        .join('\n');
    expect(sent, contains('甲'));
    expect(sent, isNot(contains('默认标题')));
    // accepted 后：body 清空、模板选择保留。
    final draft = container
        .read(composerDraftProvider.notifier)
        .draftFor(conversationId);
    expect(draft.body, '');
    expect(draft.selectedTemplatePromptId, 'tp-1');
  });

  test('模板语法无效返回 invalidTemplate，不发送且草稿完整保留', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    final template = TemplatePrompt(
      id: 'tp-bad',
      title: '损坏模板',
      content: '{{#if x == "a"}}未闭合',
      variables: const [],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '正文');
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-bad');
    container
        .read(composerDraftProvider.notifier)
        .setTemplateVariable(conversationId, 'tp-bad', 'x', 'a');

    final result = command.dispatch(
      intentFor(
        '正文',
        templatePrompt: template,
        variableValues: const {'x': 'a'},
      ),
    );
    expect(result, isA<ChatComposerRejected>());
    expect(
      (result as ChatComposerRejected).reason,
      ChatComposerRejectReason.invalidTemplate,
    );
    expect(fakeClient.requestHistory, isEmpty);
    final draft = container
        .read(composerDraftProvider.notifier)
        .draftFor(conversationId);
    expect(draft.body, '正文');
    expect(draft.selectedTemplatePromptId, 'tp-bad');
    expect(draft.templateVariableValuesByTemplateId['tp-bad'], {'x': 'a'});
  });

  test('已保存变量与正文声明冲突返回 invalidTemplate', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    final template = TemplatePrompt(
      id: 'tp-conflict',
      title: '冲突模板',
      content: '请按{{title}}输出。',
      variables: const [TemplatePromptVariable(name: '其他变量')],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '正文');

    final result = command.dispatch(intentFor('正文', templatePrompt: template));
    expect(result, isA<ChatComposerRejected>());
    expect(
      (result as ChatComposerRejected).reason,
      ChatComposerRejectReason.invalidTemplate,
    );
    expect(fakeClient.requestHistory, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '正文',
    );
  });

  test('数字值 "-" 返回 invalidTemplateValue，不发送且草稿保留', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    final template = TemplatePrompt(
      id: 'tp-num',
      title: '章节模板',
      content: '第{{章:number}}章',
      variables: const [
        TemplatePromptVariable(
          name: '章',
          defaultValue: '1',
          type: TemplatePromptVariableType.number,
        ),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '正文');

    final result = command.dispatch(
      intentFor(
        '正文',
        templatePrompt: template,
        variableValues: const {'章': '-'},
      ),
    );
    expect(result, isA<ChatComposerRejected>());
    expect(
      (result as ChatComposerRejected).reason,
      ChatComposerRejectReason.invalidTemplateValue,
    );
    expect(fakeClient.requestHistory, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '正文',
    );
  });

  test('单选值不在选项列表返回 invalidTemplateValue', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    final template = TemplatePrompt(
      id: 'tp-select',
      title: '人称模板',
      content: '请用{{人称:select|一|二|三}}。',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '正文');

    final result = command.dispatch(
      intentFor(
        '正文',
        templatePrompt: template,
        variableValues: const {'人称': '四'},
      ),
    );
    expect(result, isA<ChatComposerRejected>());
    expect(
      (result as ChatComposerRejected).reason,
      ChatComposerRejectReason.invalidTemplateValue,
    );
    expect(fakeClient.requestHistory, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '正文',
    );
  });

  test('有效单选 dispatch 持久化字符串值而非索引，draft 只清 body', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    final template = TemplatePrompt(
      id: 'tp-select',
      title: '人称模板',
      content: '请用{{人称:select|一|二|三}}。',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-select');
    fakeClient.enqueueChunks(['回复']);

    final result = command.dispatch(
      intentFor(
        '正文',
        templatePrompt: template,
        variableValues: const {'人称': '二'},
      ),
    );
    expect(result, isA<ChatComposerAccepted>());
    await (result as ChatComposerAccepted).completion;

    final conversation = container.read(activeChatConversationProvider);
    final userMessage = conversation.messages.firstWhere(
      (m) => m.role == ChatMessageRole.user,
    );
    expect(userMessage.templatePromptId, 'tp-select');
    // 持久化的是选项字符串值，不是列表索引。
    expect(userMessage.templateVariableValues['人称'], '二');
    expect(
      fakeClient.requestHistory.single.map((m) => m.content).join('\n'),
      contains('请用二。'),
    );
    final draft = container
        .read(composerDraftProvider.notifier)
        .draftFor(conversation.id);
    expect(draft.body, '');
    expect(draft.selectedTemplatePromptId, 'tp-select');
  });

  test('省略的单选默认值写入发送与编辑元数据及渲染内容', () async {
    final command = container.read(chatComposerCommandProvider);
    final template = TemplatePrompt(
      id: 'tp-select-default',
      title: '默认人称模板',
      content: '请用{{人称:select|一|二|三}}。',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '二',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );
    fakeClient.enqueueChunks(['首次回复']);

    final sendResult = command.dispatch(
      intentFor('正文', templatePrompt: template),
    );
    expect(sendResult, isA<ChatComposerAccepted>());
    await (sendResult as ChatComposerAccepted).completion;

    final conversation = container.read(activeChatConversationProvider);
    final sentUserMessage = conversation.messages.firstWhere(
      (m) => m.role == ChatMessageRole.user,
    );
    expect(sentUserMessage.templateVariableValues['人称'], '二');
    expect(
      fakeClient.requestHistory.single.map((m) => m.content).join('\n'),
      contains('请用二。'),
    );

    // 编辑既有消息：省略的单选同样以配置默认值写入编辑元数据。
    fakeClient.enqueueChunks(['编辑后回复']);
    final editResult = command.dispatch(
      intentFor(
        '新正文',
        editingMessageId: sentUserMessage.id,
        templatePrompt: template,
      ),
    );
    expect(editResult, isA<ChatComposerAccepted>());
    await (editResult as ChatComposerAccepted).completion;

    final editedConversation = container.read(activeChatConversationProvider);
    final editedUserMessage = editedConversation.messages.firstWhere(
      (m) => m.role == ChatMessageRole.user && m.content.contains('新正文'),
    );
    expect(editedUserMessage.templatePromptId, 'tp-select-default');
    expect(editedUserMessage.templateVariableValues['人称'], '二');
    expect(editedUserMessage.content, contains('请用二。'));
  });

  test('dispatchDirect 直接发送步骤文本，不消费 composer draft', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    container
        .read(composerDraftProvider.notifier)
        .setBody(conversationId, '普通草稿');
    fakeClient.enqueueChunks(['步骤回复']);

    await command.dispatchDirect(
      ChatDirectSubmitIntent(
        conversationId: conversationId,
        content: '步骤内容',
        selectedModel: model(),
        selectedPresetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
      ),
    );

    final sent = fakeClient.requestHistory.single
        .map((m) => m.content)
        .join('\n');
    expect(sent, contains('步骤内容'));
    // 普通草稿完整保留，不被消费。
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(conversationId)
          .body,
      '普通草稿',
    );
  });

  test(
    'selectTemplate 只写目标会话 draft；setReasoning/AutoRetry 更新 conversation',
    () {
      final command = container.read(chatComposerCommandProvider);
      final conversationId = container.read(activeConversationIdProvider);

      command.selectTemplate(conversationId, 'tp-1');
      expect(
        container.read(composerTemplateSelectionProvider(conversationId)),
        'tp-1',
      );
      // 其他会话不受影响。
      expect(
        container.read(composerTemplateSelectionProvider('other-conv')),
        isNull,
      );

      command.setReasoningEnabled(true);
      command.setReasoningEffort(ReasoningEffort.high);
      command.setAutoRetryEnabled(true);
      final conversation = container.read(activeChatConversationProvider);
      expect(conversation.reasoningEnabled, isTrue);
      expect(conversation.reasoningEffort, ReasoningEffort.high);
      expect(conversation.autoRetryEnabled, isTrue);
    },
  );
}
