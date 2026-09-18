import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/agent_record_codec.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late SqliteAgentStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('agent-store-');
    database = AppDatabase.forPath('${temp.path}/agent.sqlite');
    store = SqliteAgentStore(database);
    store.saveWorkspace(AgentWorkspace(id: 'a', title: '小说甲'));
    store.saveWorkspace(AgentWorkspace(id: 'b', title: '小说乙'));
  });
  tearDown(() {
    database.close();
    temp.deleteSync(recursive: true);
  });

  test('作品分别保存草稿和历史，中断恢复不会改动其他作品', () {
    final first = AgentWorkspace(
      id: 'a',
      title: '小说甲',
      draft: '初始草稿',
      history: const [LlmTextMessage(role: LlmRole.user, text: '旧输入')],
    );
    store.saveWorkspace(first);
    store.checkpoint(
      AgentRunRecord(
        id: 'old-run',
        workspaceId: 'a',
        prompt: '未完成',
        startedAt: DateTime(2026),
      ),
    );
    final second = AgentWorkspace(id: 'b', title: '小说乙', draft: '另一草稿');
    store.saveWorkspace(second);
    store.recoverInterruptedRuns();
    expect(store.loadWorkspace('b'), second);
    expect(store.loadWorkspace('a')!.draft, '初始草稿');
    expect(store.loadWorkspace('a')!.history.length, greaterThan(1));
    expect(store.listRuns('a').single.status, AgentRunStatus.interrupted);
    expect(store.listRuns('b'), isEmpty);
  });

  test('同名方案覆盖保存，资料修改类型保留稳定 ID', () {
    final config = AgentConfiguration(
      name: '克制版',
      modelId: 'main',
      preset: '简洁',
      roles: const {
        AgentRole.writer: AgentRoleSettings(
          modelId: 'writer',
          instructions: '写作规则',
        ),
      },
    );
    final v1 = store.saveConfiguration('a', config);
    final v2 = store.saveConfiguration(
      'a',
      config.copyWith(name: '抒情版', preset: '抒情'),
    );
    expect(store.listConfigurations('a'), containsAll([v2, v1]));
    store.saveConfiguration('a', config.copyWith(preset: '新的文风'));
    expect(store.listConfigurations('a'), hasLength(2));
    expect(
      store
          .listConfigurations('a')
          .singleWhere((c) => c.name == config.name)
          .preset,
      '新的文风',
    );
    expect(store.listConfigurations('b'), isEmpty);
    final card = store.writeDocument(
      'a',
      '甲',
      '作者设定',
      kind: AgentDocumentKind.characterCard,
    );
    final world = store.writeDocument(
      'a',
      '港口',
      '旧规则',
      kind: AgentDocumentKind.worldBook,
    );
    final updated = store.writeDocument('a', '港口', '新规则');
    expect(updated.id, world.id);
    expect(updated.kind, world.kind);
    expect(store.readDocument('a', '港口'), updated);
    final revisedCard = store.writeDocument(
      'a',
      '甲',
      '人物笔记',
      kind: AgentDocumentKind.document,
    );
    expect(revisedCard.id, card.id);
    expect(revisedCard.kind, AgentDocumentKind.document);
    expect(store.readDocument('a', '甲'), revisedCard);
  });

  test('执行流保留步骤类型与活动状态，旧记录可读且子任务链接按工作区隔离', () {
    final record = AgentRunRecord(
      id: 'child',
      workspaceId: 'a',
      parentId: 'root',
      prompt: '核对时间',
      startedAt: DateTime(2026),
      steps: const [
        AgentStep(label: '模型回复 1', reasoning: '当前是傍晚', isRunning: true),
        AgentStep(
          label: 'read_document',
          kind: AgentStepKind.tool,
          content: '{"arguments":{"name":"设定"}}',
        ),
      ],
    );
    store.checkpoint(record);
    expect(store.loadRun('a', 'child'), record);
    expect(store.loadRun('b', 'child'), isNull);
    final legacy = encodeAgentRun(record);
    for (final step in legacy['steps'] as List) {
      (step as Map).remove('kind');
      step.remove('isRunning');
    }
    final restored = decodeAgentRun(legacy);
    expect(restored.steps.first.kind, AgentStepKind.model);
    expect(restored.steps.last.kind, AgentStepKind.tool);
    expect(restored.steps.first.isRunning, isFalse);
    store.recoverInterruptedRuns();
    expect(store.loadRun('a', 'child')!.steps.first.isRunning, isFalse);
  });

  test('文档直接覆盖且只留一份，不同作品同名文档互不影响', () {
    store.writeDocument('a', '正文', '旧稿');
    store.writeDocument('a', '正文', '新稿');
    store.writeDocument('b', '正文', '另一部小说');
    expect(store.readDocument('a', '正文')?.content, '新稿');
    expect(store.readDocument('b', '正文')?.content, '另一部小说');
    expect(store.listDocuments('a'), hasLength(1));
    expect(
      database.connection.select(
        "SELECT * FROM agent_documents WHERE workspace_id = 'a';",
      ),
      hasLength(1),
    );
    expect(
      database.connection.select('SELECT * FROM agent_document_undo;'),
      isEmpty,
    );
    expect(
      database.connection.select(
        "SELECT name FROM sqlite_master WHERE name = 'agent_document_revisions';",
      ),
      isEmpty,
    );
  });

  test('文件库重开恢复正文与运行记录，中断调用补齐错误结果且不重复保存', () {
    final calls = [
      agentCall('written', 'write_document', {'name': '正文', 'content': '已保存'}),
      agentCall('uncertain', 'write_document', {
        'name': '另一稿',
        'content': '不确定',
      }),
    ];
    store.writeDocument('a', '正文', '已保存');
    final workspace = AgentWorkspace(
      id: 'a',
      title: '小说甲',
      modelId: 'model',
      draft: '未发送输入',
      history: [
        const LlmTextMessage(role: LlmRole.system, text: '固定规则'),
        const LlmTextMessage(role: LlmRole.user, text: '保存'),
        agentReply(calls: calls).assistantTurn!,
        LlmToolResult(
          callId: 'written',
          name: 'write_document',
          output: '{"revision":1}',
        ),
      ],
    );
    store.checkpoint(
      AgentRunRecord(
        id: 'root',
        workspaceId: 'a',
        prompt: '保存',
        startedAt: DateTime(2026),
        steps: const [
          AgentStep(label: '模型回复', content: '正文', reasoning: '独立推理'),
        ],
      ),
      workspace: workspace,
    );
    store.checkpoint(
      AgentRunRecord(
        id: 'child',
        workspaceId: 'a',
        parentId: 'root',
        role: AgentRole.writer,
        prompt: '子任务',
        startedAt: DateTime(2026),
      ),
    );
    final path = database.path;
    database.close();
    database = AppDatabase.forPath(path);
    store = SqliteAgentStore(database);
    store.recoverInterruptedRuns();
    final recovered = store.loadWorkspace('a')!;
    expect(recovered.history.take(workspace.history.length), workspace.history);
    expect(
      recovered.history.whereType<LlmToolResult>().last.callId,
      'uncertain',
    );
    expect(recovered.history.whereType<LlmToolResult>().last.isError, isTrue);
    expect(recovered.draft, '未发送输入');
    expect(
      store.listRuns('a').every((r) => r.status == AgentRunStatus.interrupted),
      isTrue,
    );
    expect(
      store
          .listRuns('a')
          .firstWhere((r) => r.id == 'root')
          .steps
          .single
          .reasoning,
      '独立推理',
    );
    expect(store.readDocument('a', '另一稿'), isNull);
    store.recoverInterruptedRuns();
    expect(store.loadWorkspace('a'), recovered);
    expect(
      jsonEncode(encodeAgentWorkspace(recovered)),
      isNot(contains(agentTestTarget.apiKey)),
    );
  });

  test('原生回放数据按值保留嵌套内容，未来记录版本显式失败', () {
    final turn = LlmAssistantTurn(
      text: '正文',
      reasoning: '摘要',
      replay: LlmReplayEnvelope(
        protocol: agentTestTarget.protocol,
        endpoint: Uri.parse(agentTestTarget.endpoint),
        model: 'test',
        items: [
          {
            'role': 'assistant',
            'content': '正文',
            'reasoning_content': '原始推理',
            'opaque': {'signature': '原样保留'},
          },
        ],
      ),
    );
    final workspace = AgentWorkspace(id: 'new', title: '小说甲', history: [turn]);
    store.saveWorkspace(workspace);
    expect(store.loadWorkspace('new'), workspace);
    // 明确测试未来格式拒绝，普通记录都通过 typed codec 构造。
    final future = encodeAgentWorkspace(workspace)..['version'] = 4;
    expect(() => decodeAgentWorkspace(future), throwsFormatException);
  });
}
