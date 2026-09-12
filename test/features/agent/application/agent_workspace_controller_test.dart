import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
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
