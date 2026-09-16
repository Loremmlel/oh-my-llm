import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

import '../agent_test_helpers.dart';

void main() {
  test('重试只调用状态模型并保留新草稿，撤回后历史输入仍来自原运行', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    var stateCalls = 0;
    final client = reviewedAgentClient((request, index) {
      if (request.tools.any((t) => t.name == 'commit_story_state')) {
        if (stateCalls++ == 0) throw const LlmException('模拟服务不可用');
        return agentReply(
          calls: [
            agentCall('commit', 'commit_story_state', {'operations': []}),
          ],
        );
      }
      return switch (index) {
        0 => agentReply(
          calls: [
            agentCall('write', 'write_document', {
              'name': '正文',
              'content': '正式正文',
            }),
          ],
        ),
        1 => agentReply(
          calls: [
            agentCall('update', 'update_story_state', {'name': '正文'}),
          ],
        ),
        _ => agentReply(text: '状态尚未保存'),
      };
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
    controller.setDraft('原开场');
    await controller.send();
    expect(
      container.read(agentWorkspaceProvider).latestRound!.status,
      AgentStoryRoundStatus.pending,
    );
    final mainCalls = client.requests
        .where((r) => !r.tools.any((t) => t.name == 'commit_story_state'))
        .length;
    controller.setDraft('待发送的新指令');
    await controller.send();
    expect(container.read(agentWorkspaceProvider).error, contains('重试状态更新'));
    await controller.send(retryStory: true);
    final state = container.read(agentWorkspaceProvider);
    expect(state.latestRound!.status, AgentStoryRoundStatus.committed);
    expect(state.workspace!.draft, '待发送的新指令');
    expect(
      client.requests.where(
        (r) => !r.tools.any((t) => t.name == 'commit_story_state'),
      ),
      hasLength(mainCalls),
    );
    final root = state.runs.singleWhere((r) => r.parentId == null);
    final originalInput = controller.runInput(root, root.steps.first);
    controller.withdrawLatestRound();
    expect(controller.runInput(root, root.steps.first), originalInput);
    expect(container.read(agentWorkspaceProvider).workspace!.draft, '原开场');
    expect(container.read(agentWorkspaceProvider).workspace!.history, isEmpty);
    expect(container.read(agentWorkspaceProvider).documents, isEmpty);
  });
}
