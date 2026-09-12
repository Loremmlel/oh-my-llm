import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
  test('应用新方案在同作品建立独立会话，旧会话的配置设定和实际输入仍可核对', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    final client = FakeAgentClient((_, _) => agentReply(text: '旧会话结果'));
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
    controller.createWorkspace();
    controller.saveDocument(
      '世界书',
      '旧版世界',
      0,
      kind: AgentDocumentKind.worldBook,
    );
    final firstConfig = controller.saveConfiguration(
      AgentConfiguration(name: '方案甲', modelId: 'model', preset: '旧文风'),
    )!;
    controller.applyConfiguration(firstConfig);
    controller.setDraft('开始写作');
    final preview = controller.previewInput();
    await controller.send();
    final first = container.read(agentWorkspaceProvider).workspace!;
    final record = container.read(agentWorkspaceProvider).runs.single;
    expect(client.requests.single.input, preview);
    expect(controller.runInput(record, record.steps.first), preview);
    controller.setDraft('旧会话待发送');
    controller.saveDocument(
      '世界书',
      '新版世界',
      1,
      kind: AgentDocumentKind.worldBook,
    );
    expect(agentInputText(controller.previewInput()), contains('旧版世界'));
    expect(agentInputText(controller.previewInput()), isNot(contains('新版世界')));
    final secondConfig = controller.saveConfiguration(
      firstConfig.copyWith(name: '方案乙', preset: '新文风'),
    )!;
    controller.applyConfiguration(secondConfig);
    final second = container.read(agentWorkspaceProvider).workspace!;
    expect(second.id, first.id);
    expect(second.sessionId, isNot(first.sessionId));
    expect(second.history, isEmpty);
    expect(container.read(agentWorkspaceProvider).runs, isEmpty);
    expect(agentInputText(controller.previewInput()), contains('新版世界'));
    expect(agentInputText(controller.previewInput()), contains('新文风'));
    expect(controller.runInput(record, record.steps.first), preview);
    controller.selectSession(first.sessionId);
    expect(container.read(agentWorkspaceProvider).workspace!.draft, '旧会话待发送');
    expect(
      container.read(agentWorkspaceProvider).workspace!.configuration,
      firstConfig,
    );
    expect(container.read(agentWorkspaceProvider).runs.single.id, record.id);
  });

  test('保存终态失败时保留可见错误，不用旧的运行中记录覆盖终态', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = _FailingStore(database);
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
    controller.createWorkspace();
    controller.configure(modelId: 'model');
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
    controller.createWorkspace();
    controller.configure(modelId: 'model');
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
