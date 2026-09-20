import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/application/agent_script_context.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_context_batch.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_script.dart';

import '../agent_test_helpers.dart';
import '../agent_story_test_helpers.dart';

String scriptMarkdown(String name, [String body = '三周后揭晓投稿人']) =>
    '---\nname: $name\ndescription: 加入文学社后相关\n---\n# 剧本\n$body';

void main() {
  late AppDatabase db;
  late SqliteAgentStore store;
  setUp(() {
    db = AppDatabase.inMemory();
    store = SqliteAgentStore(db);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
  });
  tearDown(() => db.close());
  AgentDocument script(String name, [String body = '三周后揭晓投稿人']) =>
      store.writeDocument(
        'novel',
        '',
        scriptMarkdown(name, body),
        kind: AgentDocumentKind.script,
      );
  AgentRuntime runtime(FakeAgentClient client) => AgentRuntime(
    client: client,
    store: store,
    workspace: store.loadWorkspace('novel')!,
    roleModels: agentTestModels,
    onUpdate: (_) {},
  );

  test('首次只发现元信息，新增修改退出目录都追加且重载保留发现状态', () async {
    final first = script('秋季', '未读剧本秘密');
    final client = FakeAgentClient((_, _) => agentReply());
    await runtime(client).run('讨论');
    expect(agentInputText(client.requests.single.input), contains('秋季'));
    expect(
      agentInputText(client.requests.single.input),
      isNot(contains('未读剧本秘密')),
    );
    final original = store.loadWorkspace('novel')!;
    expect(original.knownScripts, contains(first.id));
    expect(agentScriptUpdates(original, store.listDocuments('novel')), isEmpty);

    script('冬季');
    store.writeDocument(
      'novel',
      first.name,
      scriptMarkdown('秋季', '正文已经修改'),
      documentId: first.id,
    );
    final beforePreview = store.loadWorkspace('novel')!;
    final preview = agentScriptUpdates(
      beforePreview,
      store.listDocuments('novel'),
    );
    expect(
      agentScriptUpdates(
        store.loadWorkspace('novel')!,
        store.listDocuments('novel'),
      ),
      preview,
    );
    await runtime(client).run('继续');
    final input = client.requests.last.input;
    final start = input.indexOf(original.history.first);
    expect(input.skip(start).take(original.history.length), original.history);
    expect(input[start + original.history.length], preview.single);
    expect(
      agentInputText(input.skip(original.history.length).toList()),
      contains('updated'),
    );
    expect(agentInputText(input), isNot(contains('正文已经修改')));
    expect(
      agentScriptUpdates(
        store.loadWorkspace('novel')!,
        store.listDocuments('novel'),
      ),
      isEmpty,
    );

    store.writeDocument(
      'novel',
      first.name,
      '改为普通资料',
      kind: AgentDocumentKind.document,
      documentId: first.id,
    );
    await runtime(client).run('移出');
    expect(agentInputText(client.requests.last.input), contains('removed'));
    expect(
      store.loadWorkspace('novel')!.knownScripts,
      isNot(contains(first.id)),
    );
  });

  test('压缩后补充有效剧本目录和备忘，逐轮撤回恢复来源之前的备忘', () async {
    final doc = script('秋季');
    Future<void> remember(
      AgentScriptStatus status,
      List<String> sources,
    ) async {
      final client = FakeAgentClient(
        (_, index) => index == 0
            ? agentReply(
                calls: [
                  agentCall('read', 'read_script', {'script_id': doc.id}),
                  agentCall('memo', 'record_script_progress', {
                    'script_id': doc.id,
                    'status': status.name,
                    'notes': '${status.label}：9 月初收到投稿，三周后发生争议',
                    'source_round_ids': sources,
                  }),
                ],
              )
            : agentReply(),
      );
      final result = await runtime(client).run('核对剧本');
      expect(result.status, AgentRunStatus.completed, reason: result.error);
      expect(
        client.requests.last.input.whereType<LlmToolResult>().last.isError,
        isFalse,
      );
    }

    await remember(AgentScriptStatus.planned, []);
    final first = seedProseFloor(store, 1);
    await remember(AgentScriptStatus.active, [first.id]);
    final second = seedProseFloor(store, 2);
    await remember(AgentScriptStatus.completed, [first.id, second.id]);
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'summary',
        historyEnd: store.loadRun('novel', second.id)!.historyEnd!,
        roundIds: [first.id, second.id],
        summary: '日常继续。',
      ),
    );
    final loaded = store.loadWorkspace('novel')!;
    final input = buildAgentMainContext(
      loaded,
      batch: store.readContextBatch('novel'),
    );
    expect(input, isNot(contains(agentProseMessage(first))));
    expect(
      input
          .whereType<LlmToolResult>()
          .where((r) => r.name == 'read_script')
          .map((r) => (jsonDecode(r.output) as Map)['content']),
      everyElement(doc.content),
    );
    expect(agentInputText(input), contains('9 月初收到投稿'));
    expect(loaded.scriptProgress[doc.id]!.status, AgentScriptStatus.completed);
    final nextClient = FakeAgentClient((request, _) {
      final catalog = request.input.whereType<LlmTextMessage>().singleWhere(
        (m) => m.text.startsWith('当前完整剧本目录及有效进度'),
      );
      expect(catalog.text, contains(doc.name));
      expect(catalog.text, contains('9 月初收到投稿'));
      expect(catalog.text, contains('completed'));
      return agentReply(text: '继续');
    });
    expect(
      (await runtime(nextClient).run('压缩后继续')).status,
      AgentRunStatus.completed,
    );

    store.withdrawStoryRound('novel', second.id);
    expect(
      store.loadWorkspace('novel')!.scriptProgress[doc.id]!.status,
      AgentScriptStatus.active,
    );
    store.withdrawStoryRound('novel', first.id);
    expect(
      store.loadWorkspace('novel')!.scriptProgress[doc.id]!.status,
      AgentScriptStatus.planned,
    );
    expect(
      agentInputText(store.loadWorkspace('novel')!.history),
      isNot(contains('正在推进：')),
    );
  });

  test('未读当前稿、非法来源与未提交的完成判断不能写入备忘', () async {
    final doc = script('秋季');
    final client = FakeAgentClient(
      (_, index) => index == 0
          ? agentReply(
              calls: [
                agentCall('unread', 'record_script_progress', {
                  'script_id': doc.id,
                  'status': 'planned',
                  'notes': '计划',
                  'source_round_ids': [],
                }),
                agentCall('read', 'read_script', {'script_id': doc.id}),
                agentCall('missing-source', 'record_script_progress', {
                  'script_id': doc.id,
                  'status': 'completed',
                  'notes': '无证据完成',
                  'source_round_ids': [],
                }),
                agentCall('wrong-source', 'record_script_progress', {
                  'script_id': doc.id,
                  'status': 'active',
                  'notes': '候选稿',
                  'source_round_ids': ['not-committed'],
                }),
                agentCall('wrong-script', 'read_script', {
                  'script_id': 'outside-workspace',
                }),
              ],
            )
          : agentReply(),
    );
    await runtime(client).run('核对');
    final results = client.requests.last.input
        .whereType<LlmToolResult>()
        .toList();
    expect(results.map((r) => r.isError), [true, false, true, true, true]);
    expect(store.loadWorkspace('novel')!.scriptProgress, isEmpty);
  });

  test('写作审查状态闭环只接收委派要求，子任务与通用工具不能读取或覆盖剧本', () async {
    final doc = script('秋季', '剧本独占秘密');
    var mainCalls = 0, writerCalls = 0, reviewerCalls = 0;
    final client = FakeAgentClient((request, _) {
      final tools = request.tools.map((t) => t.name).toSet();
      if (tools.contains('spawn_subagent')) {
        return agentReply(
          calls: mainCalls++ == 0
              ? [
                  agentCall('read', 'read_script', {'script_id': doc.id}),
                ]
              : [
                  agentCall('writer', 'spawn_subagent', {
                    'role': 'writer',
                    'task': '本轮只写筹备会，不跳过争议，并检查此要求',
                    'background': false,
                  }),
                ],
        );
      }
      expect(agentInputText(request.input), isNot(contains('剧本独占秘密')));
      expect(tools, isNot(contains('read_script')));
      if (tools.contains('commit_story_state')) {
        return agentReply(
          calls: [
            agentCall('commit', 'commit_story_state', {'operations': []}),
          ],
        );
      }
      if (tools.contains('submit_review')) {
        if (reviewerCalls++ == 0) {
          return agentReply(
            calls: [
              agentCall('bypass', 'read_document', {'name': doc.name}),
            ],
          );
        }
        expect(request.input.whereType<LlmToolResult>().last.isError, isTrue);
        return agentReply(
          calls: [
            agentCall('verdict', 'submit_review', {
              'approved': true,
              'feedback': '符合本轮要求',
            }),
          ],
        );
      }
      if (writerCalls++ == 0) {
        return agentReply(
          calls: [
            agentCall('list', 'list_documents', {}),
            agentCall('forbidden', 'read_script', {'script_id': doc.id}),
            agentCall('overwrite', 'write_document', {
              'name': doc.name,
              'content': '破坏剧本',
            }),
          ],
        );
      }
      if (writerCalls == 2) {
        final results = request.input.whereType<LlmToolResult>().toList();
        expect(jsonDecode(results[0].output), isEmpty);
        expect(results.skip(1).every((r) => r.isError), isTrue);
        return agentReply(
          calls: [
            agentCall('save', 'write_document', {
              'name': '正文',
              'content': '筹备会上发生争议。',
            }),
            agentCall('review', 'review_document', {
              'name': '正文',
              'task': '核对不跳过争议',
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
    final result = await runtime(client).run('开始');
    expect(result.status, AgentRunStatus.completed, reason: result.error);
    expect(result.content, '筹备会上发生争议。');
    expect(store.readDocument('novel', doc.name), doc);
  });
}
