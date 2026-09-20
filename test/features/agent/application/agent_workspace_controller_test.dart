import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/features/agent/domain/agent_context_batch.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_input_encoder.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';
import '../agent_story_test_helpers.dart';

void main() {
  test('重命名作品保留草稿和配置，重新读取仍生效', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    final first = AgentWorkspace(id: 'novel', title: '旧作品', draft: '原草稿');
    store.saveWorkspace(first);
    final container = ProviderContainer(
      overrides: [agentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.setDraft('尚未落盘的草稿');
    controller.renameWorkspace(first.id, ' 雾港 ');
    expect(
      store.loadWorkspace(first.id),
      first.copyWith(title: '雾港', draft: '尚未落盘的草稿'),
    );
    controller.renameWorkspace(first.id, '  ');
    expect(container.read(agentWorkspaceProvider).error, '名称不能为空。');
  });

  test('应用配置直接更新作品并保留历史草稿及原调用输入', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    const secondTarget = LlmRequestTarget(
      protocol: LlmApiProtocol.chatCompletions,
      endpoint: 'https://example.com/v1/chat/completions',
      apiKey: '',
      model: 'new-model',
    );
    final client = FakeAgentClient((request, _) {
      encodeLlmInput(request, Uri.parse(request.target.endpoint));
      return agentReply(text: '本轮结果', target: request.target);
    });
    final container = ProviderContainer(
      overrides: [
        agentStoreProvider.overrideWithValue(store),
        agentClientProvider.overrideWithValue(client),
        agentModelsProvider.overrideWithValue(const [
          AgentModel(
            id: 'model',
            label: '测试模型',
            target: agentTestTarget,
            options: LlmGenerationOptions(),
          ),
          AgentModel(
            id: 'second-model',
            label: '新模型',
            target: secondTarget,
            options: LlmGenerationOptions(),
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.createWorkspace();
    controller.saveDocument('世界书', '旧版世界', kind: AgentDocumentKind.worldBook);
    controller.saveDocument(
      '',
      '---\nname: 秋季剧本\ndescription: 开学后相关\n---\n三周后发生争议。',
      kind: AgentDocumentKind.script,
    );
    final firstConfig = controller.saveConfiguration(
      AgentConfiguration(name: '方案甲', modelId: 'model', preset: '旧文风'),
    )!;
    controller.applyConfiguration(firstConfig);
    controller.setDraft('开始写作');
    final preview = controller.previewInput();
    expect(controller.previewInput(), preview);
    expect(
      container.read(agentWorkspaceProvider).workspace!.knownScripts,
      isEmpty,
    );
    await controller.send();
    final first = container.read(agentWorkspaceProvider).workspace!;
    final record = container.read(agentWorkspaceProvider).runs.single;
    expect(client.requests.single.input, preview);
    expect(controller.runInput(record, record.steps.first), preview);
    controller.setDraft('待发送草稿');
    controller.saveDocument('世界书', '新版世界', kind: AgentDocumentKind.worldBook);
    expect(agentInputText(controller.previewInput()), isNot(contains('旧版世界')));
    expect(agentInputText(controller.previewInput()), contains('新版世界'));
    final secondConfig = controller.saveConfiguration(
      firstConfig.copyWith(name: '方案乙', preset: '新文风', modelId: 'second-model'),
    )!;
    controller.applyConfiguration(secondConfig);
    final second = container.read(agentWorkspaceProvider).workspace!;
    expect(second.id, first.id);
    expect(second.history, first.history);
    expect(second.knownScripts, first.knownScripts);
    expect(agentInputText(controller.previewInput()), contains('秋季剧本'));
    expect(container.read(agentWorkspaceProvider).runs.single.id, record.id);
    expect(agentInputText(controller.previewInput()), contains('新版世界'));
    expect(agentInputText(controller.previewInput()), contains('新文风'));
    expect(controller.runInput(record, record.steps.first), preview);
    expect(container.read(agentWorkspaceProvider).workspace!.draft, '待发送草稿');
    expect(
      container.read(agentWorkspaceProvider).workspace!.configuration,
      secondConfig,
    );
    expect(container.read(agentWorkspaceProvider).runs.single.id, record.id);
    final convertedPreview = controller.previewInput();
    await controller.send(retryReplyId: record.id);
    final retried = container.read(agentWorkspaceProvider).runs.single;
    expect(retried.id, record.id);
    expect(retried.modelId, 'second-model');
    expect(retried.modelLabel, '新模型');
    expect(retried.status, AgentRunStatus.completed);
    expect(client.requests.last.target, secondTarget);
    controller.setDraft('继续讨论');
    await controller.send();
    expect(container.read(agentWorkspaceProvider).runs, hasLength(2));
    expect(
      () => encodeLlmInput(
        LlmRequest(target: secondTarget, input: convertedPreview),
        Uri.parse(secondTarget.endpoint),
      ),
      returnsNormally,
    );
  });

  test('压缩后更换模型的预览与实际请求保持工具标识和输入一致', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    List<LlmInputItem> exchange(String id) => [
      agentReply(
        calls: [
          agentCall(id, 'read_document', {'name': '正文'}),
        ],
      ).assistantTurn!,
      LlmToolResult(callId: id, name: 'read_document', output: '原工具结果'),
    ];
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
    store.saveWorkspace(
      store.loadWorkspace('novel')!.copyWith(history: exchange('before')),
    );
    final floor = seedProseFloor(store, 1);
    store.saveWorkspace(
      store
          .loadWorkspace('novel')!
          .copyWith(
            modelId: 'new',
            draft: '继续',
            history: [
              ...store.loadWorkspace('novel')!.history,
              ...exchange('after'),
            ],
          ),
    );
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'summary',
        roundIds: [floor.id],
        historyEnd: 3,
        summary: '累计摘要',
      ),
    );
    const target = LlmRequestTarget(
      protocol: LlmApiProtocol.chatCompletions,
      endpoint: 'https://example.com/v1/chat/completions',
      apiKey: '',
      model: 'new-model',
    );
    final client = FakeAgentClient((request, _) {
      encodeLlmInput(request, Uri.parse(target.endpoint));
      return agentReply(text: '新模型结果', target: target);
    });
    final container = ProviderContainer(
      overrides: [
        agentStoreProvider.overrideWithValue(store),
        agentClientProvider.overrideWithValue(client),
        agentModelsProvider.overrideWithValue(const [
          AgentModel(
            id: 'new',
            label: '新模型',
            target: target,
            options: LlmGenerationOptions(),
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    final expected = controller.previewInput();
    await controller.send();
    expect(client.requests.single.input, expected);
    expect(agentInputText(expected), contains('累计摘要'));
    expect(expected.whereType<LlmToolResult>(), hasLength(1));
  });

  test('保存终态失败时保留可见错误，不用旧的运行中记录覆盖终态', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = _FailingStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', modelId: 'model'),
    );
    final client = FakeAgentClient((_, index) {
      if (index == 0) store.failCheckpoints = true;
      return agentReply(text: '已生成但未保存');
    });
    final container = ProviderContainer(
      overrides: [
        agentStoreProvider.overrideWithValue(store),
        agentClientProvider.overrideWithValue(client),
        agentModelsProvider.overrideWithValue(const [
          AgentModel(
            id: 'model',
            label: '测试模型',
            target: agentTestTarget,
            options: LlmGenerationOptions(),
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.setDraft('写作');
    await controller.send();
    final state = container.read(agentWorkspaceProvider);
    expect(state.busy, isFalse);
    expect(state.runs.single.status, AgentRunStatus.failed);
    expect(state.runs.single.error, contains('未能保存'));
    expect(state.runs.single.content, '已生成但未保存');
    store.failCheckpoints = false;
    controller.setDraft('后续任务');
    await controller.send();
    expect(client.requests, hasLength(2));
    expect(
      store
          .listRuns(state.workspace!.id)
          .any((r) => r.status == AgentRunStatus.running),
      isFalse,
    );
  });

  test('输入超过上限时保留草稿并重新启用提交，不会留下假运行状态', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', modelId: 'model'),
    );
    final client = FakeAgentClient((_, _) => agentReply());
    final container = ProviderContainer(
      overrides: [
        agentStoreProvider.overrideWithValue(store),
        agentClientProvider.overrideWithValue(client),
        agentModelsProvider.overrideWithValue(const [
          AgentModel(
            id: 'model',
            label: '测试模型',
            target: agentTestTarget,
            options: LlmGenerationOptions(),
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.setDraft('字' * 65536);
    await controller.send();
    expect(container.read(agentWorkspaceProvider).busy, isFalse);
    expect(container.read(agentWorkspaceProvider).workspace!.draft, isNotEmpty);
    expect(client.requests, isEmpty);
    expect(container.read(agentWorkspaceProvider).error, contains('64 KiB'));
  });
}

class _FailingStore extends SqliteAgentStore {
  _FailingStore(super.database);
  bool failCheckpoints = false;
  @override
  void checkpoint(AgentRunRecord run, {AgentWorkspace? workspace}) {
    if (failCheckpoints) throw StateError('注入存储失败');
    super.checkpoint(run, workspace: workspace);
  }
}
