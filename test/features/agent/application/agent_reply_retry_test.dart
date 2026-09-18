import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
  test('重新打开后重试沿用原指令且覆盖原回复，失败后可再次重试并保留草稿', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', modelId: 'model', draft: '原指令'),
    );
    final client = FakeAgentClient((request, index) {
      if (index == 1) throw const LlmException('模拟断网');
      return agentReply(text: index == 0 ? '旧回复' : '新回复');
    });
    ProviderContainer open() => ProviderContainer(
      overrides: [
        agentStoreProvider.overrideWithValue(SqliteAgentStore(database)),
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
    var container = open();
    await container.read(agentWorkspaceProvider.notifier).send();
    final original = store.listRuns('novel').single;
    container.dispose();
    container = open();
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.setDraft('下一条草稿');
    await controller.send(retryReplyId: original.id);
    expect(store.listRuns('novel').single.status, AgentRunStatus.failed);
    await controller.send(retryReplyId: original.id);
    final saved = store.listRuns('novel').single;
    expect(saved.id, original.id);
    expect(saved.content, '新回复');
    expect(saved.status, AgentRunStatus.completed);
    expect(store.loadWorkspace('novel')!.draft, '下一条草稿');
    expect(
      store
          .loadWorkspace('novel')!
          .history
          .whereType<LlmAssistantTurn>()
          .single
          .text,
      '新回复',
    );
    for (final request in client.requests) {
      expect(request.input.whereType<LlmTextMessage>().last.text, '原指令');
      expect(request.input.whereType<LlmAssistantTurn>(), isEmpty);
    }
  });
}
