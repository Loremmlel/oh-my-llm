import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_context_batch.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

import 'agent_story_store_test.dart'
    show prepareRound, finishRound, seedOperations;

void main() {
  late AppDatabase database;
  late SqliteAgentStore store;
  setUp(() {
    database = AppDatabase.inMemory();
    store = SqliteAgentStore(database);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
  });
  tearDown(() => database.close());

  test('重试已采用正文原子撤回状态与文档并删除旧后代，使相关总结失效', () {
    final original = store.writeDocument('novel', '正文', '原正文');
    final round = prepareRound(store, 'round');
    store.commitStoryRound(
      'novel',
      round.id,
      round.stateAgentId,
      seedOperations(),
    );
    finishRound(store, round);
    store.checkpoint(store.loadRun('novel', round.id)!.copyWith(historyEnd: 1));
    store.checkpoint(
      AgentRunRecord(
        id: 'grandchild',
        workspaceId: 'novel',
        parentId: round.stateAgentId,
        role: AgentRole.reviewer,
        prompt: '检查',
        startedAt: DateTime(2026),
        status: AgentRunStatus.completed,
      ),
    );
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'summary',
        roundIds: [round.id],
        historyEnd: 1,
        summary: '累计摘要',
      ),
    );
    store.saveDraft('novel', '未发送的草稿');
    final replacement = store.resetLatestReply('novel', round.id);
    expect(replacement.id, round.id);
    expect(replacement.content, isEmpty);
    expect(store.listRuns('novel'), hasLength(1));
    expect(store.readStoryRound('novel', round.id), isNull);
    expect(store.readStoryState('novel').rows, isEmpty);
    expect(store.readStoryState('novel').revision, greaterThan(1));
    expect(store.readDocument('novel', '正文'), original);
    expect(
      store.loadWorkspace('novel')!.history,
      round.beforeWorkspace.history,
    );
    expect(store.loadWorkspace('novel')!.draft, '未发送的草稿');
    expect(
      store.listContextBatches('novel').single.status,
      AgentContextBatchStatus.invalidated,
    );
    expect(
      store.loadRun('novel', round.id)!.beforeWorkspace,
      round.beforeWorkspace,
    );
  });

  test('撤回尚未采用的工具写入，保留用户后来修改的文档且重复重试不恢复旧回复', () {
    final before = store.loadWorkspace('novel')!;
    final root = AgentRunRecord(
      id: 'run',
      workspaceId: 'novel',
      prompt: '原指令',
      startedAt: DateTime(2026),
      beforeWorkspace: before,
    );
    store.checkpoint(root);
    store.writeDocument('novel', '候选', '工具写入', sourceRunId: root.id);
    store.writeDocument('novel', '手动修改', '工具写入', sourceRunId: root.id);
    store.writeDocument('novel', '手动修改', '用户新版');
    store.checkpoint(
      root.copyWith(status: AgentRunStatus.failed, content: '旧回复'),
      workspace: before.copyWith(
        history: [const LlmTextMessage(role: LlmRole.user, text: '原指令')],
      ),
    );
    store.resetLatestReply('novel', root.id);
    expect(store.readDocument('novel', '候选'), isNull);
    expect(store.readDocument('novel', '手动修改')!.content, '用户新版');
    expect(store.loadWorkspace('novel')!.history, isEmpty);
    final reopened = SqliteAgentStore(database);
    final retry = reopened.resetLatestReply('novel', root.id);
    expect(retry.content, isEmpty);
    expect(reopened.listRuns('novel'), hasLength(1));
  });

  test('持久化重试占位失败时正文状态历史与子任务全部恢复', () {
    final round = prepareRound(store, 'round');
    store.commitStoryRound(
      'novel',
      round.id,
      round.stateAgentId,
      seedOperations(),
    );
    finishRound(store, round);
    final runs = store.listRuns('novel');
    final workspace = store.loadWorkspace('novel');
    final state = store.readStoryState('novel');
    database.connection.execute(
      "CREATE TRIGGER fail_retry BEFORE UPDATE ON agent_runs BEGIN SELECT RAISE(ABORT, 'disk failure'); END;",
    );
    expect(() => store.resetLatestReply('novel', round.id), throwsException);
    expect(store.listRuns('novel'), runs);
    expect(store.loadWorkspace('novel'), workspace);
    expect(store.readStoryState('novel'), state);
    expect(store.readDocument('novel', '正文'), round.document);
    expect(
      store.readStoryRound('novel', round.id)!.status,
      AgentStoryRoundStatus.committed,
    );
  });

  test('旧主任务、子任务、跨作品、运行中和缺少快照的旧记录均不能重试', () {
    final before = store.loadWorkspace('novel')!;
    AgentRunRecord record(String id, int time, {String? parentId}) =>
        AgentRunRecord(
          id: id,
          workspaceId: 'novel',
          prompt: '指令',
          parentId: parentId,
          beforeWorkspace: before,
          startedAt: DateTime(2026).add(Duration(seconds: time)),
          status: AgentRunStatus.completed,
        );
    store.checkpoint(record('old', 1));
    store.checkpoint(record('latest', 2));
    store.checkpoint(record('child', 3, parentId: 'latest'));
    for (final id in ['old', 'child', 'missing']) {
      expect(
        () => store.resetLatestReply('novel', id),
        throwsA(isA<AgentWorkspaceException>()),
      );
    }
    expect(
      () => store.resetLatestReply('other', 'latest'),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.checkpoint(
      record(
        'child',
        3,
        parentId: 'latest',
      ).copyWith(status: AgentRunStatus.running),
    );
    expect(
      () => store.resetLatestReply('novel', 'latest'),
      throwsA(isA<AgentWorkspaceException>()),
    );
    store.checkpoint(record('child', 3, parentId: 'latest'));
    store.checkpoint(
      AgentRunRecord(
        id: 'legacy',
        workspaceId: 'novel',
        prompt: '旧记录',
        startedAt: DateTime(2027),
        status: AgentRunStatus.completed,
      ),
    );
    expect(
      () => store.resetLatestReply('novel', 'legacy'),
      throwsA(isA<AgentWorkspaceException>()),
    );
    expect(store.listRuns('novel'), hasLength(4));
  });
}
