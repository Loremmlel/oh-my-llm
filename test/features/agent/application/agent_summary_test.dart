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
    roleModels: agentTestModels,
    onUpdate: (_) {},
  );
  List<LlmInputItem> preview() => buildAgentMainContext(
    store.loadWorkspace('novel')!,
    batch: store.readContextBatch('novel'),
  );

  test('超过五十楼仍按完整任务边界压缩并可恢复，后续原生记录和实际输入保留', () async {
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
      historyEnd: 12,
      summary: '前十二楼累计摘要',
    );
    store.saveContextBatch('novel', batch);
    expect(store.listStoryRounds('novel'), hasLength(60));
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
    final run = await runtime(client).summarize(
      AgentContextBatch(id: 'first', roundIds: [first.id], historyEnd: 1),
    );
    expect(run.status, AgentRunStatus.completed);
    expect(run.role, AgentRole.summarizer);
    expect(store.loadRun('novel', run.id)!.summaryBatch!.roundIds, [first.id]);
    expect(store.loadWorkspace('novel'), before);
    final text = agentInputText(preview());
    expect(text.indexOf('保留下来的前情摘要'), lessThan(text.indexOf('正式正文 2')));
    expect(text, isNot(contains('round_id="floor-1"')));
    expect(store.listStoryRounds('novel'), hasLength(2));
  });

  test('总结失败取消或应用事务失败时保持旧摘要与范围', () async {
    final first = seedProseFloor(store, 1);
    final batch = AgentContextBatch(
      id: 'first',
      roundIds: [first.id],
      summary: '原摘要',
      historyEnd: 1,
    );
    store.saveContextBatch('novel', batch);
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
    expect(store.readContextBatch('novel'), batch);
  });

  test('累计摘要替换旧摘要，撤回覆盖末楼使整份摘要失效并恢复原文', () {
    final first = seedProseFloor(store, 1), second = seedProseFloor(store, 2);
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'a',
        roundIds: [first.id],
        historyEnd: 1,
        summary: '第一份',
      ),
    );
    expect(
      () => store.saveContextBatch(
        'novel',
        AgentContextBatch(
          id: 'invalid',
          roundIds: [second.id],
          historyEnd: 2,
          summary: '跳过开头',
        ),
      ),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'b',
        roundIds: [first.id, second.id],
        historyEnd: 2,
        summary: '累计第二份',
      ),
    );
    expect(store.readContextBatch('novel')!.id, 'b');
    expect(agentInputText(preview()), contains('累计第二份'));
    expect(agentInputText(preview()), isNot(contains('第一份')));
    store.withdrawStoryRound('novel', second.id);
    expect(
      store.readContextBatch('novel')!.status,
      AgentContextBatchStatus.invalidated,
    );
    expect(agentInputText(preview()), contains('正式正文 1'));
    expect(agentInputText(preview()), isNot(contains('累计第二份')));
  });

  test('再次压缩仅合并前摘要与新增原稿，覆盖任务的工具副本与旧状态全部退出上下文', () async {
    final native = agentReply(
      calls: [
        agentCall('write', 'write_document', {'content': '工具正文副本'}),
      ],
    ).assistantTurn!;
    store.saveWorkspace(
      store
          .loadWorkspace('novel')!
          .copyWith(
            history: [
              const LlmTextMessage(role: LlmRole.user, text: '旧状态快照'),
              native,
              LlmToolResult(
                callId: 'write',
                name: 'write_document',
                output: '旧工具结果',
              ),
            ],
          ),
    );
    seedProseFloor(store, 1);
    seedProseFloor(store, 2);
    final original = store.loadWorkspace('novel')!;
    final client = FakeAgentClient((request, index) {
      final text = agentInputText(request.input);
      if (index == 0) {
        expect(text, contains('正式正文 1'));
        return agentReply(text: '首轮累计摘要');
      }
      expect(text, contains('首轮累计摘要'));
      expect(text, contains('正式正文 2'));
      expect(text, isNot(contains('正式正文 1')));
      expect(text, isNot(contains('旧工具结果')));
      return agentReply(text: '合并后的唯一摘要');
    });
    expect(
      (await runtime(client).summarize(
        AgentContextBatch(id: 'a', roundIds: ['floor-1'], historyEnd: 4),
      )).status,
      AgentRunStatus.completed,
    );
    expect(preview().whereType<LlmAssistantTurn>(), isEmpty);
    expect(preview().whereType<LlmToolResult>(), isEmpty);
    expect(agentInputText(preview()), isNot(contains('旧状态快照')));
    expect(
      (await runtime(client).summarize(
        AgentContextBatch(
          id: 'b',
          roundIds: ['floor-1', 'floor-2'],
          historyEnd: 5,
        ),
      )).status,
      AgentRunStatus.completed,
    );
    expect(store.readContextBatch('novel')!.id, 'b');
    final text = agentInputText(preview());
    expect(text, contains('合并后的唯一摘要'));
    expect(text, isNot(contains('首轮累计摘要')));
    expect(text, isNot(contains('<adopted_prose')));
    expect(store.loadWorkspace('novel'), original);
    expect(store.readDocument('novel', '正文')!.content, '正式正文 2');
    expect(store.readStoryState('novel').revision, 2);
  });

  test('重开数据库保留摘要来源与恢复选择，作品之间不互相影响', () {
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
      historyEnd: 1,
      status: AgentContextBatchStatus.restored,
    );
    disk.saveContextBatch('novel', batch);
    disk.saveWorkspace(AgentWorkspace(id: 'other', title: '另一作品'));
    persisted.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    final restored = SqliteAgentStore(reopened);
    expect(restored.readContextBatch('novel'), batch);
    expect(restored.readContextBatch('other'), isNull);
  });
}
