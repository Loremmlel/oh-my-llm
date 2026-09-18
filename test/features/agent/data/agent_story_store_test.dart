import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

void main() {
  late AppDatabase database;
  late SqliteAgentStore store;
  setUp(() {
    database = AppDatabase.inMemory();
    store = SqliteAgentStore(database);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
    store.saveWorkspace(AgentWorkspace(id: 'other', title: '另一部小说'));
  });
  tearDown(() => database.close());

  test('事务尾部保存轮次失败时回滚全部状态，正文可用于重试', () {
    final round = prepareRound(store, 'first');
    // 故障注入：新状态已经写入后，故意让同一事务的轮次保存失败。
    database.connection.execute(
      "CREATE TRIGGER fail_round BEFORE UPDATE ON agent_story_rounds WHEN NEW.status = 'committed' BEGIN SELECT RAISE(ABORT, 'disk failure'); END;",
    );
    final operations = seedOperations();
    expect(
      () => store.commitStoryRound(
        'novel',
        round.id,
        round.stateAgentId,
        operations,
      ),
      throwsException,
    );
    expect(store.readStoryState('novel').rows, isEmpty);
    expect(
      store.latestStoryRound('novel')!.status,
      AgentStoryRoundStatus.pending,
    );
    expect(store.readDocument('novel', '正文'), round.document);
    database.connection.execute('DROP TRIGGER fail_round;');
    final saved = store.commitStoryRound(
      'novel',
      round.id,
      round.stateAgentId,
      operations,
    );
    expect(saved.status, AgentStoryRoundStatus.committed);
    expect(store.readStoryState('novel').rows, hasLength(3));
    expect(
      store.commitStoryRound('novel', round.id, round.stateAgentId, operations),
      saved,
    );
    expect(
      () => store.commitStoryRound('novel', round.id, round.stateAgentId, []),
      throwsA(isA<AgentWorkspaceException>()),
    );
  });

  test('跨作品和旧状态任务不能提交，正文版本变化后保留待处理轮次', () {
    final round = prepareRound(store, 'first');
    expect(
      () => store.commitStoryRound('other', round.id, round.stateAgentId, []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    expect(
      () => store.commitStoryRound('novel', round.id, 'unbound', []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    final actor = store.loadRun('novel', round.stateAgentId)!;
    store.checkpoint(actor.copyWith(status: AgentRunStatus.cancelled));
    expect(
      () => store.commitStoryRound('novel', round.id, actor.id, []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.checkpoint(actor);
    store.prepareStoryRound(round.copyWith(stateAgentId: 'retry-agent'));
    expect(
      () => store.commitStoryRound('novel', round.id, round.stateAgentId, []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.checkpoint(
      AgentRunRecord(
        id: 'retry-agent',
        workspaceId: 'novel',
        parentId: round.id,
        role: AgentRole.state,
        prompt: '重试',
        startedAt: DateTime(2026),
      ),
    );
    store.writeDocument('novel', '正文', '手工新版本');
    expect(
      () => store.commitStoryRound('novel', round.id, 'retry-agent', []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    expect(store.readStoryState('novel').revision, 0);
    expect(
      store.latestStoryRound('novel')!.status,
      AgentStoryRoundStatus.pending,
    );
  });

  test('撤回恢复三张表和原指令，隐藏本轮文档而保留历史，版本继续递增', () {
    final first = prepareRound(store, 'first');
    store.commitStoryRound(
      'novel',
      first.id,
      first.stateAgentId,
      seedOperations(),
    );
    finishRound(store, first);
    final old = store.readStoryState('novel');
    final second = prepareRound(store, 'second', content: '乙仍然不知道秘密');
    store.commitStoryRound('novel', second.id, second.stateAgentId, [
      AgentStateOperation(
        kind: AgentStateOperationKind.update,
        table: AgentStateTable.scene,
        rowId: old.rows.first.id,
        cells: {'place': '操场'},
      ),
      AgentStateOperation(
        kind: AgentStateOperationKind.delete,
        table: AgentStateTable.characters,
        rowId: old.rows[1].id,
      ),
      AgentStateOperation(
        kind: AgentStateOperationKind.insert,
        table: AgentStateTable.events,
        cells: {'event': '离开图书馆'},
      ),
    ]);
    finishRound(store, second);
    expect(
      () => store.withdrawStoryRound('other', second.id),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.withdrawStoryRound('novel', second.id);
    expect(store.readStoryState('novel').rows, old.rows);
    expect(store.readStoryState('novel').revision, greaterThan(old.revision));
    expect(
      store.loadWorkspace('novel')!.history,
      second.beforeWorkspace.history,
    );
    expect(store.loadWorkspace('novel')!.draft, '原指令 second');
    expect(store.readDocument('novel', '正文'), first.document);
    expect(store.readStoryRound('novel', second.id)!.document, second.document);
    expect(
      store.readStoryRound('novel', second.id)!.status,
      AgentStoryRoundStatus.withdrawn,
    );
    expect(
      () => store.commitStoryRound('novel', second.id, second.stateAgentId, []),
      throwsA(isA<AgentWorkspaceException>()),
    );
    final nextDocument = store.writeDocument('novel', '正文', '重新写');
    expect(nextDocument.id, first.document.id);
    expect(nextDocument.content, '重新写');
    store.withdrawStoryRound('novel', first.id);
    expect(store.readStoryState('novel').rows, isEmpty);
  });

  test('空操作保存也可撤回，未完成轮次可放弃且不启动逆向模型调用', () {
    final first = prepareRound(store, 'empty');
    store.commitStoryRound('novel', first.id, first.stateAgentId, []);
    finishRound(store, first);
    store.withdrawStoryRound('novel', first.id);
    final pending = prepareRound(store, 'pending');
    finishRound(store, pending);
    store.withdrawStoryRound('novel', pending.id);
    expect(store.latestStoryRound('novel'), isNull);
    expect(
      store.readStoryRound('novel', pending.id)!.status,
      AgentStoryRoundStatus.discarded,
    );
    expect(store.readDocument('novel', '正文'), isNull);
    expect(store.loadWorkspace('novel')!.draft, '原指令 pending');
  });

  test('重开数据库恢复已提交状态和待处理轮次，不重复更新', () {
    final directory = Directory.systemTemp.createTempSync('story-reopen-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/story.sqlite';
    final disk = AppDatabase.forPath(path);
    final original = SqliteAgentStore(disk);
    original.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
    final first = prepareRound(original, 'first');
    final saved = original.commitStoryRound(
      'novel',
      first.id,
      first.stateAgentId,
      seedOperations(),
    );
    finishRound(original, first);
    final pending = prepareRound(original, 'pending');
    disk.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    final restored = SqliteAgentStore(reopened);
    restored.recoverInterruptedRuns();
    expect(restored.readStoryState('novel'), saved.afterState);
    expect(restored.latestStoryRound('novel'), pending);
    expect(
      restored.loadRun('novel', pending.stateAgentId)!.status,
      AgentRunStatus.interrupted,
    );
  });
}

List<AgentStateOperation> seedOperations() => [
  AgentStateOperation(
    kind: AgentStateOperationKind.insert,
    table: AgentStateTable.scene,
    cells: {'place': '图书馆'},
  ),
  AgentStateOperation(
    kind: AgentStateOperationKind.insert,
    table: AgentStateTable.characters,
    cells: {'name': '乙', 'knowledge': '不知道秘密'},
  ),
  AgentStateOperation(
    kind: AgentStateOperationKind.insert,
    table: AgentStateTable.events,
    cells: {'event': '甲选择保密'},
  ),
];

AgentStoryRound prepareRound(
  SqliteAgentStore store,
  String id, {
  String content = '甲没有告诉乙秘密',
}) {
  final before = store.loadWorkspace('novel')!.copyWith(draft: '原指令 $id');
  store.checkpoint(
    AgentRunRecord(
      id: id,
      workspaceId: before.id,
      prompt: before.draft,
      startedAt: DateTime(2026),
    ),
    workspace: before.copyWith(
      history: [
        ...before.history,
        LlmTextMessage(role: LlmRole.user, text: before.draft),
      ],
    ),
  );
  final document = store.writeDocument(
    before.id,
    '正文',
    content,
    sourceRunId: id,
  );
  final round = store.prepareStoryRound(
    AgentStoryRound(
      id: id,
      beforeWorkspace: before,
      document: document,
      beforeState: store.readStoryState(before.id),
      stateAgentId: '$id-state',
    ),
  );
  store.checkpoint(
    AgentRunRecord(
      id: round.stateAgentId,
      workspaceId: before.id,
      parentId: id,
      role: AgentRole.state,
      prompt: '更新状态',
      startedAt: DateTime(2026),
    ),
  );
  return round;
}

void finishRound(SqliteAgentStore store, AgentStoryRound round) {
  for (final id in [round.id, round.stateAgentId]) {
    store.checkpoint(
      store.loadRun('novel', id)!.copyWith(status: AgentRunStatus.completed),
    );
  }
}
