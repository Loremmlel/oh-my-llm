import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/application/agent_model.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
  test('角色推演使用独立模型并读取完整设定，子任务只读且设定不能被工具覆盖', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final store = SqliteAgentStore(db);
    final workspace = AgentWorkspace(id: 'n', title: '雾港');
    store.saveWorkspace(workspace);
    final card = store.writeDocument(
      'n',
      '阿弥',
      '秘密身份是继承人',
      expectedRevision: 0,
      kind: AgentDocumentKind.characterCard,
    );
    store.writeDocument(
      'n',
      '公开规则',
      '日落关门',
      expectedRevision: 0,
      kind: AgentDocumentKind.worldBook,
    );
    store.writeDocument(
      'n',
      '作者秘密',
      '王室密令',
      expectedRevision: 0,
      kind: AgentDocumentKind.worldBook,
    );
    final childTarget = LlmRequestTarget(
      protocol: agentTestTarget.protocol,
      endpoint: agentTestTarget.endpoint,
      apiKey: 'child-private-key',
      model: 'character-model',
    );
    final client = FakeAgentClient((request, index) {
      if (index == 0) {
        expect(agentInputText(request.input), contains('王室密令'));
        return agentReply(
          calls: [
            agentCall('s', 'spawn_subagent', {
              'role': 'character',
              'task': '推演阿弥的行动',
              'background': false,
            }),
            agentCall('w', 'write_document', {
              'name': '作者秘密',
              'content': '擅自修改',
              'expected_revision': 1,
            }),
          ],
        );
      }
      if (index == 1) {
        expect(request.target, childTarget);
        final input = agentInputText(request.input);
        expect(input, contains(card.content));
        expect(input, contains('日落关门'));
        expect(input, contains('王室密令'));
        return agentReply(
          target: childTarget,
          calls: [
            agentCall('l', 'list_documents', {}),
            agentCall('r', 'read_document', {'name': '作者秘密'}),
            agentCall('self', 'read_document', {'name': '阿弥'}),
            agentCall('bad', 'write_document', {
              'name': '稿',
              'content': '越权',
              'expected_revision': 0,
            }),
          ],
        );
      }
      if (index == 2) {
        expect(request.target, childTarget);
        final results = request.input.whereType<LlmToolResult>().toList();
        expect(results[0].output, contains('作者秘密'));
        expect(results[1].isError, isFalse);
        expect(results[1].output, contains('王室密令'));
        expect(results[2].output, contains(card.content));
        expect(results[3].isError, isTrue);
        return agentReply(target: childTarget, text: '候选行动');
      }
      expect(request.target, agentTestTarget);
      expect(request.input.whereType<LlmToolResult>().last.isError, isTrue);
      return agentReply(text: '已取得候选');
    });
    final runtime = AgentRuntime(
      client: client,
      store: store,
      workspace: workspace,
      target: agentTestTarget,
      roleModels: {
        AgentRole.coordinator: const AgentModel(
          id: 'main',
          label: '主模型',
          target: agentTestTarget,
          options: LlmGenerationOptions(),
        ),
        AgentRole.character: AgentModel(
          id: 'character',
          label: '角色专用模型',
          target: childTarget,
          options: LlmGenerationOptions(),
        ),
      },
      onUpdate: (_) {},
    );
    expect((await runtime.run('安排角色推演')).status, AgentRunStatus.completed);
    expect(client.requests, hasLength(4));
    expect(store.readDocument('n', '作者秘密')!.content, '王室密令');
    expect(store.readDocument('n', '稿'), isNull);
    final child = store.listRuns('n').singleWhere((r) => r.parentId != null);
    expect(child.modelLabel, '角色专用模型');
    final inputCount = child.steps.first.inputItemCount!;
    expect(child.childHistory.take(inputCount), client.requests[1].input);
    expect(child.tools, client.requests[1].tools);
    expect(
      agentInputText(child.childHistory),
      isNot(contains(childTarget.apiKey)),
    );
  });
}
