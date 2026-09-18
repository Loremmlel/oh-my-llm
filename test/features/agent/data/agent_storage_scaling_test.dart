import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

void main() {
  late AppDatabase database;
  late _ReadTrackingStore store;
  setUp(() {
    database = AppDatabase.inMemory();
    store = _ReadTrackingStore(database);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
  });
  tearDown(() => database.close());

  test('草稿单独落盘，不重写作品历史且不覆盖随后保存的上下文', () {
    final container = ProviderContainer(
      overrides: [agentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    controller.setDraft('待发送');
    final updated = store
        .loadWorkspace('novel')!
        .copyWith(
          history: const [LlmTextMessage(role: LlmRole.user, text: '新的历史')],
        );
    store.saveWorkspace(updated);
    // 故障注入只禁止重写历史载体，独立保存草稿仍应成功。
    database.connection.execute('''
      CREATE TRIGGER reject_history_write BEFORE UPDATE OF record_json ON agent_workspaces
      BEGIN SELECT RAISE(ABORT, '不允许草稿重写历史'); END;
    ''');
    controller.flushDraft();
    expect(store.loadWorkspace('novel'), updated.copyWith(draft: '待发送'));
  });

  test('作品目录只读取元数据，不加载任一作品历史', () {
    store.saveWorkspace(AgentWorkspace(id: 'other', title: '另一本小说'));
    store.workspaceReads = 0;
    expect(
      store.listWorkspaces().map((w) => w.title),
      containsAll(['小说', '另一本小说']),
    );
    expect(store.workspaceReads, 0);
  });

  test('连续轮次共享历史前缀，保存体积不随快照数量重复累计正文', () {
    const count = 40, bytesPerFloor = 16384;
    var workspace = store.loadWorkspace('novel')!;
    final originals = <AgentStoryRound>[];
    for (var i = 0; i < count; i++) {
      workspace = workspace.copyWith(
        history: [
          ...workspace.history,
          LlmTextMessage(role: LlmRole.user, text: '$i:${'a' * bytesPerFloor}'),
        ],
      );
      final root = AgentRunRecord(
        id: 'run-$i',
        workspaceId: 'novel',
        prompt: '继续',
        startedAt: DateTime(2026).add(Duration(seconds: i)),
        inputHistory: [
          LlmTextMessage(role: LlmRole.system, text: '第 $i 轮的设定'),
          ...workspace.history,
        ],
      );
      store.checkpoint(root, workspace: workspace);
      final document = store.writeDocument(
        'novel',
        '正文',
        '第 $i 楼',
        sourceRunId: root.id,
      );
      final actor = AgentRunRecord(
        id: 'state-$i',
        workspaceId: 'novel',
        parentId: root.id,
        role: AgentRole.state,
        prompt: '更新',
        startedAt: root.startedAt,
      );
      store.checkpoint(actor);
      final round = store.prepareStoryRound(
        AgentStoryRound(
          id: root.id,
          beforeWorkspace: workspace,
          document: document,
          beforeState: store.readStoryState('novel'),
          stateAgentId: actor.id,
        ),
      );
      originals.add(store.commitStoryRound('novel', round.id, actor.id, []));
      store.checkpoint(root.copyWith(status: AgentRunStatus.completed));
      store.checkpoint(actor.copyWith(status: AgentRunStatus.completed));
    }
    final pages =
        database.connection.select('PRAGMA page_count').single['page_count']
            as int;
    final pageSize =
        database.connection.select('PRAGMA page_size').single['page_size']
            as int;
    expect(
      pages * pageSize,
      lessThan(count * bytesPerFloor * 4 + 512 * 1024),
      reason: '历史、运行输入和撤回快照应共享已保存前缀，保留全文不需要重复复制',
    );
    expect(store.listStoryRounds('novel'), originals.reversed.toList());
    expect(
      store.loadRun('novel', 'run-0')!.inputHistory!.skip(1).toList(),
      originals.first.beforeWorkspace.history,
    );
    store.withdrawStoryRound('novel', originals.last.id);
    expect(
      store.loadWorkspace('novel')!.history,
      originals.last.beforeWorkspace.history,
    );
  });
}

class _ReadTrackingStore extends SqliteAgentStore {
  _ReadTrackingStore(super.database);
  int workspaceReads = 0;
  @override
  AgentWorkspace? loadWorkspace(String id) {
    workspaceReads++;
    return super.loadWorkspace(id);
  }
}
