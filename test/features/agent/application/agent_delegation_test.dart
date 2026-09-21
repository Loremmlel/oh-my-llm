import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

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

  test('嵌套状态失败只重试绑定的状态任务，保留新草稿和原写作归属', () async {
    var stateCalls = 0;
    final client = FakeAgentClient((request, _) {
      final names = request.tools.map((t) => t.name).toSet();
      if (names.contains('submit_review')) {
        return agentReply(
          calls: [
            agentCall('reviewed', 'submit_review', {
              'approved': true,
              'feedback': '通过',
            }),
          ],
        );
      }
      if (names.contains('commit_story_state')) {
        if (stateCalls++ == 0) throw StateError('模拟状态调用失败');
        return agentReply(
          calls: [
            agentCall('commit', 'commit_story_state', {'operations': []}),
          ],
        );
      }
      if (request.input.whereType<LlmToolResult>().isNotEmpty) {
        return agentReply(text: '状态尚未保存');
      }
      if (names.contains('spawn_subagent')) {
        return agentReply(
          calls: [
            agentCall('spawn', 'spawn_subagent', {
              'role': 'writer',
              'task': '写作',
              'background': false,
            }),
          ],
        );
      }
      return agentReply(
        calls: [
          agentCall('write', 'write_document', {
            'name': '正文',
            'content': '绑定的最终正文',
          }),
          agentCall('review', 'review_document', {'name': '正文', 'task': '审查'}),
          agentCall('deliver', 'update_story_state', {'name': '正文'}),
        ],
      );
    });
    final failed = await runtime(client).run('原写作指令');
    expect(failed.status, AgentRunStatus.failed);
    final pending = store.latestStoryRound('novel')!;
    final previousCalls = client.requests.length;
    store.saveWorkspace(store.loadWorkspace('novel')!.copyWith(draft: '下一轮草稿'));
    final result = await runtime(client).retryStory(pending);
    expect(result.status, AgentRunStatus.completed, reason: result.error);
    expect(client.requests.length, previousCalls + 1);
    expect(result.request.inputHistory, failed.request.inputHistory);
    expect(store.latestStoryRound('novel')!.writerRunId, pending.writerRunId);
    expect(store.loadRun('novel', pending.writerRunId!)!.content, '绑定的最终正文');
    expect(store.loadWorkspace('novel')!.draft, '下一轮草稿');
  });

  test('写作直接审查改稿并交付，两轮主历史续接而子任务重新组装', () async {
    var round = 0, writerCalls = 0;
    final mainRequests = <LlmRequest>[];
    final firstWriterInputs = <List<LlmInputItem>>[];
    final client = FakeAgentClient((request, _) {
      final names = request.tools.map((t) => t.name).toSet();
      if (names.contains('spawn_subagent')) {
        mainRequests.add(request);
        round++;
        writerCalls = 0;
        return agentReply(
          calls: [
            agentCall('spawn-$round', 'spawn_subagent', {
              'role': 'writer',
              'task': '写第 $round 楼',
              'background': false,
            }),
          ],
        );
      }
      if (names.contains('submit_review')) {
        expect(request.input.whereType<LlmAssistantTurn>(), isEmpty);
        final approved = !agentInputText(request.input).contains('废稿秘密');
        return agentReply(
          calls: [
            agentCall('verdict', 'submit_review', {
              'approved': approved,
              'feedback': approved ? '通过' : '角色没有获知秘密的依据',
            }),
          ],
        );
      }
      if (names.contains('commit_story_state')) {
        expect(agentInputText(request.input), contains('最终正文 $round'));
        expect(agentInputText(request.input), isNot(contains('废稿秘密')));
        return agentReply(
          calls: [
            agentCall('commit', 'commit_story_state', {'operations': []}),
          ],
        );
      }
      final call = writerCalls++;
      if (call == 0) {
        firstWriterInputs.add(request.input);
        return agentReply(
          calls: [
            agentCall('draft', 'write_document', {
              'name': '正文',
              'content': '废稿秘密 $round',
            }),
            agentCall('review-draft', 'review_document', {
              'name': '正文',
              'task': '检查人物知情',
            }),
          ],
        );
      }
      if (call == 1) {
        expect(
          request.input.whereType<LlmToolResult>().last.output,
          contains('false'),
        );
        return agentReply(
          calls: [
            agentCall('revise', 'write_document', {
              'name': '正文',
              'content': '最终正文 $round',
            }),
            agentCall('review-final', 'review_document', {
              'name': '正文',
              'task': '检查改稿',
            }),
          ],
        );
      }
      return agentReply(
        calls: [
          agentCall('deliver', 'update_story_state', {'name': '正文'}),
        ],
      );
    });
    final first = await runtime(client).run('开始写作');
    expect(first.status, AgentRunStatus.completed, reason: first.error);
    final original = store.loadWorkspace('novel')!.history;
    final second = await runtime(client).run('继续写作');
    expect(second.status, AgentRunStatus.completed, reason: second.error);
    expect(second.content, '最终正文 2');
    expect(mainRequests, hasLength(2));
    expect(mainRequests.last.input, containsAllInOrder(original));
    expect(firstWriterInputs.last.whereType<LlmAssistantTurn>(), isEmpty);
    expect(agentInputText(firstWriterInputs.last), contains('最终正文 1'));
    expect(agentInputText(firstWriterInputs.last), isNot(contains('废稿秘密')));
    final runs = store.listRuns('novel');
    final writer = runs.singleWhere(
      (r) => r.parentId == second.id && r.role == AgentRole.writer,
    );
    expect(
      runs.where((r) => r.parentId == writer.id).map((r) => r.role),
      containsAll([AgentRole.reviewer, AgentRole.state]),
    );
    expect(store.latestStoryRound('novel')!.writerRunId, writer.id);
    expect(store.readStoryState('novel').revision, 2);
    expect(
      original.whereType<LlmToolResult>().single.output,
      isNot(contains('最终正文')),
    );
    store.withdrawStoryRound('novel', second.id);
    expect(store.readDocument('novel', '正文')!.content, '最终正文 1');
    expect(store.loadWorkspace('novel')!.history, original);
  });

  test('审查通过后修改稿件不能沿用结论，改稿预算耗尽不提交剧情', () async {
    var writer = 0;
    final client = FakeAgentClient((request, _) {
      if (request.tools.any((t) => t.name == 'submit_review')) {
        return agentReply(
          calls: [
            agentCall('yes', 'submit_review', {
              'approved': true,
              'feedback': '通过',
            }),
          ],
        );
      }
      if (request.tools.any((t) => t.name == 'spawn_subagent')) {
        return request.input.whereType<LlmToolResult>().isEmpty
            ? agentReply(
                calls: [
                  agentCall('spawn', 'spawn_subagent', {
                    'role': 'writer',
                    'task': '写作',
                    'background': false,
                  }),
                ],
              )
            : agentReply(text: '交付未完成');
      }
      if (writer++ == 0) {
        return agentReply(
          calls: [
            agentCall('write', 'write_document', {
              'name': '正文',
              'content': '通过稿',
            }),
            agentCall('review', 'review_document', {
              'name': '正文',
              'task': '审查',
            }),
            agentCall('change', 'write_document', {
              'name': '正文',
              'content': '改动稿',
            }),
            agentCall('deliver', 'update_story_state', {'name': '正文'}),
          ],
        );
      }
      expect(request.input.whereType<LlmToolResult>().last.isError, isTrue);
      return agentReply(text: '未通过');
    });
    await runtime(client).run('写作');
    expect(store.latestStoryRound('novel'), isNull);
    expect(store.readStoryState('novel').revision, 0);
    expect(
      store
          .listRuns('novel')
          .singleWhere((r) => r.role == AgentRole.writer)
          .status,
      AgentRunStatus.failed,
    );
  });

  test('角色工具不能读取其他角色卡、普通文档和范围外状态', () async {
    final card = store.writeDocument(
      'novel',
      '甲',
      '甲的设定',
      kind: AgentDocumentKind.characterCard,
    );
    store.writeDocument(
      'novel',
      '乙',
      '乙的秘密',
      kind: AgentDocumentKind.characterCard,
    );
    store.writeDocument('novel', '正文', '作者全知剧情');
    var child = 0;
    final client = FakeAgentClient((request, _) {
      if (request.tools.any((t) => t.name == 'spawn_character')) {
        return request.input.whereType<LlmToolResult>().isEmpty
            ? agentReply(
                calls: [
                  agentCall('spawn', 'spawn_character', {
                    'card_id': card.id,
                    'state_row_ids': <String>[],
                    'task': '扮演甲',
                    'background': false,
                  }),
                ],
              )
            : agentReply(text: '收到');
      }
      expect(agentInputText(request.input), isNot(contains('乙的秘密')));
      expect(agentInputText(request.input), isNot(contains('作者全知剧情')));
      if (child++ == 0) {
        return agentReply(
          calls: [
            agentCall('other', 'read_document', {'name': '乙'}),
            agentCall('state', 'read_story_state', {}),
          ],
        );
      }
      expect(request.input.whereType<LlmToolResult>().first.isError, isTrue);
      return agentReply(text: '甲的行动');
    });
    expect((await runtime(client).run('推演')).status, AgentRunStatus.completed);
  });

  test('停止覆盖嵌套审查，未完成稿不交付且所有工具往返闭合', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final client = FakeAgentClient((request, _) async {
      if (request.tools.any((t) => t.name == 'spawn_subagent')) {
        return agentReply(
          calls: [
            agentCall('spawn', 'spawn_subagent', {
              'role': 'writer',
              'task': '写作',
              'background': false,
            }),
          ],
        );
      }
      if (request.tools.any((t) => t.name == 'submit_review')) {
        entered.complete();
        await release.future;
        return agentReply(text: '迟到');
      }
      return agentReply(
        calls: [
          agentCall('write', 'write_document', {
            'name': '正文',
            'content': '候选稿',
          }),
          agentCall('review', 'review_document', {'name': '正文', 'task': '审查'}),
        ],
      );
    });
    final run = runtime(client);
    final future = run.run('写作');
    await entered.future;
    run.cancel();
    await future;
    release.complete();
    expect(store.latestStoryRound('novel'), isNull);
    for (final record in store.listRuns('novel')) {
      expect(record.status, isNot(AgentRunStatus.running));
      final history = record.request.inputHistory ?? record.childHistory;
      expect(closePendingAgentTools(history), history);
    }
  });
}
