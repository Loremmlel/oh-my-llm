import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/data/agent_record_codec.dart';
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

  test('较早任务的统计字段异常不阻塞作品，保留已报告 Token 并标记不完整', () {
    const tokens = LlmUsage(inputTokens: 100, outputTokens: 20);
    final invalidFields = [
      ('missing-calls', null, tokens.toJson()),
      ('string-calls', '1', tokens.toJson()),
      ('negative-calls', -1, tokens.toJson()),
      ('string-usage', 1, 'invalid'),
      ('number-usage', 1, 7),
      ('missing-usage', null, null),
    ];
    for (final (id, calls, usage) in invalidFields) {
      final record = AgentRunRecord(
        id: id,
        workspaceId: 'novel',
        prompt: '继续',
        startedAt: DateTime(2026),
        status: AgentRunStatus.completed,
      );
      store.checkpoint(record);
      // 故障样本只破坏较早记录的统计字段，保留当前格式和原始正文。
      final json = encodeAgentRun(record)..['usage'] = usage;
      if (calls == null) {
        json.remove('modelCalls');
      } else {
        json['modelCalls'] = calls;
      }
      database.connection.execute(
        'UPDATE agent_runs SET record_json = ? WHERE id = ?;',
        [jsonEncode(json), id],
      );
    }
    // 当前时间线只加载最近 50 条；较早记录仍属于全作品用量的读取范围。
    for (var i = 0; i < 50; i++) {
      store.checkpoint(
        AgentRunRecord(
          id: 'valid-$i',
          workspaceId: 'novel',
          prompt: '继续',
          startedAt: DateTime(2026).add(Duration(seconds: i + 1)),
          status: AgentRunStatus.completed,
        ),
      );
    }
    final usages = store.readRunUsages('novel');
    for (final id in ['missing-calls', 'string-calls', 'negative-calls']) {
      expect(usages[id]?.modelCalls, 0);
      expect(usages[id]?.tokens, tokens);
      expect(usages[id]?.incomplete, isTrue);
    }
    expect(usages['string-usage']?.tokens, isNull);
    expect(usages['number-usage']?.tokens, isNull);
    final container = ProviderContainer(
      overrides: [agentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    expect(container.read(agentWorkspaceProvider).workspace?.id, 'novel');
    expect(container.read(agentWorkspaceProvider).error, isEmpty);
    final summary = container
        .read(agentWorkspaceProvider.notifier)
        .usageSummary;
    expect(summary.tokens.totalTokens, 360);
    expect(summary.incomplete, isTrue);
  });

  test('对话用量累计超过时间线分页的全部根任务与子任务，切换作品隔离统计', () {
    for (var i = 0; i < 51; i++) {
      store.checkpoint(
        AgentRunRecord(
          id: 'run-$i',
          workspaceId: 'novel',
          prompt: '继续',
          startedAt: DateTime(2026).add(Duration(seconds: i)),
          status: AgentRunStatus.completed,
          usage: const AgentRunUsage(
            modelCalls: 1,
            tokens: LlmUsage(
              inputTokens: 100,
              cachedInputTokens: 50,
              outputTokens: 20,
            ),
          ),
        ),
      );
    }
    store.checkpoint(
      AgentRunRecord(
        id: 'child',
        workspaceId: 'novel',
        parentId: 'run-0',
        prompt: '写作',
        startedAt: DateTime(2026),
        status: AgentRunStatus.completed,
        usage: const AgentRunUsage(
          modelCalls: 1,
          tokens: LlmUsage(
            inputTokens: 200,
            cachedInputTokens: 50,
            outputTokens: 40,
          ),
        ),
      ),
    );
    expect(store.listRuns('novel'), hasLength(50));
    final container = ProviderContainer(
      overrides: [agentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentWorkspaceProvider.notifier);
    expect(controller.usageSummary.tokens.totalTokens, 6360);
    controller.setDraft('保留累计值');
    expect(controller.usageSummary.tokens.totalTokens, 6360);
    controller.createWorkspace();
    expect(controller.usageSummary.tokens.totalTokens, isNull);
    controller.selectWorkspace('novel');
    expect(controller.usageSummary.tokens.totalTokens, 6360);
  });

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
        request: AgentRunRequestSnapshot(
          inputHistory: [
            LlmTextMessage(role: LlmRole.system, text: '第 $i 轮的设定'),
            ...workspace.history,
          ],
        ),
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
      store.loadRun('novel', 'run-0')!.request.inputHistory!.skip(1).toList(),
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
