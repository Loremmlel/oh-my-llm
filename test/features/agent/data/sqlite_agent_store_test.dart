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

  test('文档保留历史版本，冲突拒绝覆盖，不同工作区同名文档互不影响', () {
    store.writeDocument('a', '正文', '旧稿', expectedRevision: 0);
    store.writeDocument('a', '正文', '新稿', expectedRevision: 1);
    store.writeDocument('b', '正文', '另一部小说', expectedRevision: 0);
    expect(
      () => store.writeDocument('a', '正文', '过期覆盖', expectedRevision: 1),
      throwsA(isA<AgentWorkspaceException>()),
    );
    expect(store.readDocument('a', '正文')?.content, '新稿');
    expect(store.readDocument('a', '正文', revision: 1)?.content, '旧稿');
    expect(store.readDocument('b', '正文')?.content, '另一部小说');
    expect(store.listDocuments('a'), hasLength(1));
  });

  test('文件库重开恢复正文与运行记录，中断调用补齐错误结果且不重复保存', () {
    final calls = [
      agentCall('written', 'write_document', {
        'name': '正文',
        'content': '已保存',
        'expected_revision': 0,
      }),
      agentCall('uncertain', 'write_document', {
        'name': '另一稿',
        'content': '不确定',
        'expected_revision': 0,
      }),
    ];
    store.writeDocument('a', '正文', '已保存', expectedRevision: 0);
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
    expect(store.readDocument('a', '正文')?.revision, 1);
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
    final workspace = AgentWorkspace(id: 'a', title: '小说甲', history: [turn]);
    store.saveWorkspace(workspace);
    expect(store.loadWorkspace('a'), workspace);
    // 明确测试未来格式拒绝，普通记录都通过 typed codec 构造。
    final future = encodeAgentWorkspace(workspace)..['version'] = 2;
    expect(() => decodeAgentWorkspace(future), throwsFormatException);
  });
}
