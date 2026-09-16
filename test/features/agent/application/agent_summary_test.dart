import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_context_batch.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_story_test_helpers.dart';
import '../agent_test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqliteAgentStore store;
  setUp(() {
    db = AppDatabase.inMemory();
    store = SqliteAgentStore(db);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
  });
  tearDown(() => db.close());
  AgentRuntime runtime(FakeAgentClient client) => AgentRuntime(
    client: client,
    store: store,
    workspace: store.loadWorkspace('novel')!,
    target: agentTestTarget,
    onUpdate: (_) {},
  );
  List<LlmInputItem> preview() => buildAgentMainContext(
    store.loadWorkspace('novel')!,
    batches: store.listContextBatches('novel', 'initial'),
    rounds: store.listStoryRounds('novel', 'initial'),
  );

  test('超过五十条记录仍按真实楼层隐藏，保留原生副本与实际输入并可恢复', () async {
    final rounds = [for (var i = 1; i <= 60; i++) seedProseFloor(store, i)];
    final original = store.loadWorkspace('novel')!;
    final native = agentReply(
      calls: [
        agentCall('read', 'read_document', {'name': '正文'}),
      ],
    ).assistantTurn!;
    final result = LlmToolResult(
      callId: 'read',
      name: 'read_document',
      output: '正式正文 1 原生副本',
    );
    store.saveWorkspace(
      original.copyWith(history: [...original.history, native, result]),
    );
    final batch = AgentContextBatch(
      id: 'batch',
      roundIds: rounds.take(12).map((r) => r.id).toList(),
    );
    store.saveContextBatch('novel', 'initial', batch);
    expect(store.listStoryRounds('novel', 'initial'), hasLength(60));
    expect(preview(), containsAllInOrder([native, result]));
    expect(agentInputText(preview()), isNot(contains('round_id="floor-1"')));
    expect(agentInputText(preview()), contains('round_id="floor-13"'));
    final client = FakeAgentClient((request, _) {
      expect(request.input, contains(native));
      return agentReply(text: '普通讨论');
    });
    final run = await runtime(client).run('讨论');
    final actualInput = run.inputHistory;
    store.saveContextBatch(
      'novel',
      'initial',
      batch.copyWith(status: AgentContextBatchStatus.restored),
    );
    expect(agentInputText(preview()), contains('round_id="floor-1"'));
    expect(store.loadRun('novel', run.id)!.inputHistory, actualInput);
    expect(store.readStoryState('novel').revision, 60);
  });

  test('总结只读取选定原稿和用户输入，独立保存后摘要位于正文前且不增加主历史', () async {
    final first = seedProseFloor(store, 1);
    seedProseFloor(store, 2);
    final before = store.loadWorkspace('novel')!;
    final client = FakeAgentClient((request, _) {
      final input = agentInputText(request.input);
      expect(input, contains('正式正文 1'));
      expect(input, contains('写第 1 楼'));
      expect(input, isNot(contains('正式正文 2')));
      expect(input, isNot(contains('最新剧情状态')));
      expect(request.tools, isEmpty);
      return agentReply(text: '保留下来的前情摘要');
    });
    final run = await runtime(client)
        .summarize(AgentContextBatch(id: 'first', roundIds: [first.id]));
    expect(run.status, AgentRunStatus.completed);
    expect(run.role, AgentRole.summarizer);
    expect(store.loadRun('novel', run.id)!.summaryBatch!.roundIds, [first.id]);
    expect(store.loadWorkspace('novel'), before);
    final text = agentInputText(preview());
    expect(text.indexOf('保留下来的前情摘要'), lessThan(text.indexOf('正式正文 2')));
    expect(text, isNot(contains('round_id="floor-1"')));
    expect(store.listStoryRounds('novel', 'initial'), hasLength(2));
  });

  test('总结失败取消或应用事务失败时保持旧摘要与范围', () async {
    final first = seedProseFloor(store, 1);
    final batch = AgentContextBatch(
      id: 'first',
      roundIds: [first.id],
      summary: '原摘要',
    );
    store.saveContextBatch('novel', 'initial', batch);
    final empty = await runtime(FakeAgentClient((_, _) => agentReply(text: '')))
        .summarize(batch);
    expect(empty.status, AgentRunStatus.failed);
    final entered = Completer<void>(), release = Completer<void>();
    final run = runtime(
      FakeAgentClient((_, _) async {
        entered.complete();
        await release.future;
        return agentReply(text: '迟到摘要');
      }),
    );
    final future = run.summarize(batch);
    await entered.future;
    run.cancel();
    expect((await future).status, AgentRunStatus.cancelled);
    release.complete();
    db.connection.execute(
      "CREATE TRIGGER fail_summary BEFORE UPDATE ON agent_context_batches BEGIN SELECT RAISE(ABORT, 'save failure'); END;",
    );
    final unsaved = await runtime(
      FakeAgentClient((_, _) => agentReply(text: '新摘要')),
    ).summarize(batch);
    expect(unsaved.status, AgentRunStatus.failed);
    expect(store.loadRun('novel', unsaved.id)!.error, contains('尚未应用'));
    expect(store.listContextBatches('novel', 'initial'), [batch]);
  });

  test('撤回覆盖楼层只使关联批次失效，无关选择仍保留并拒绝交叉范围', () {
    final first = seedProseFloor(store, 1), second = seedProseFloor(store, 2);
    final a = AgentContextBatch(id: 'a', roundIds: [first.id], summary: '第一批');
    final b = AgentContextBatch(id: 'b', roundIds: [second.id], summary: '第二批');
    store.saveContextBatch('novel', 'initial', a);
    store.saveContextBatch('novel', 'initial', b);
    expect(
      () => store.saveContextBatch(
        'novel',
        'initial',
        AgentContextBatch(id: 'overlap', roundIds: [first.id, second.id]),
      ),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.withdrawStoryRound('novel', 'initial', second.id);
    final batches = store.listContextBatches('novel', 'initial');
    expect(batches.first, a);
    expect(batches.last.status, AgentContextBatchStatus.invalidated);
    expect(agentInputText(preview()), contains('第一批'));
    expect(agentInputText(preview()), isNot(contains('第二批')));
  });

  test('重开数据库保留摘要来源与恢复选择，会话之间不互相影响', () {
    final directory = Directory.systemTemp.createTempSync('agent-summary-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/story.sqlite';
    final persisted = AppDatabase.forPath(path);
    final disk = SqliteAgentStore(persisted);
    disk.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
    final floor = seedProseFloor(disk, 1);
    final batch = AgentContextBatch(
      id: 'b',
      roundIds: [floor.id],
      summary: '旧摘要',
      status: AgentContextBatchStatus.restored,
    );
    disk.saveContextBatch('novel', 'initial', batch);
    disk.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', sessionId: 'other'),
    );
    persisted.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    final restored = SqliteAgentStore(reopened);
    expect(restored.listContextBatches('novel', 'initial'), [batch]);
    expect(restored.listContextBatches('novel', 'other'), isEmpty);
  });
}
