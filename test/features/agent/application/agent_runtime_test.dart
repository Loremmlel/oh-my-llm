import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../agent_test_helpers.dart';

void main() {
  late AppDatabase database;
  late SqliteAgentStore store;
  late AgentWorkspace workspace;
  setUp(() {
    database = AppDatabase.inMemory();
    store = SqliteAgentStore(database);
    workspace = AgentWorkspace(id: 'workspace', title: '小说');
    store.saveWorkspace(workspace);
  });
  tearDown(() => database.close());

  test('实时思考与等待中的委派可见，停止后保留子任务部分推理', () async {
    final mainStarted = Completer<void>(), childStarted = Completer<void>();
    final visible = Completer<void>(), childVisible = Completer<void>();
    final mainStream = StreamController<LlmEvent>(
      onListen: mainStarted.complete,
    );
    final childStream = StreamController<LlmEvent>(
      onListen: childStarted.complete,
    );
    addTearDown(mainStream.close);
    addTearDown(childStream.close);
    final snapshots = <String, AgentRunRecord>{};
    final runner = AgentRuntime(
      client: StreamingAgentClient(
        (_, index) => index == 0 ? mainStream.stream : childStream.stream,
      ),
      store: store,
      workspace: workspace,
      target: agentTestTarget,
      onUpdate: (record) {
        snapshots[record.id] = record;
        if (record.steps.any((s) => s.reasoning == '阿弥并不知道钥匙的位置') &&
            !childVisible.isCompleted) {
          childVisible.complete();
        }
        if (record.steps.any((s) => s.reasoning == '先确认角色知情边界') &&
            !visible.isCompleted) {
          visible.complete();
        }
      },
    );
    final running = runner.run('委派审稿');
    await mainStarted.future;
    mainStream.add(const LlmEvent(reasoningDelta: '先确认角色知情边界'));
    await visible.future;
    expect(snapshots.values.single.steps.last.isRunning, isTrue);
    mainStream.add(
      LlmCompleted(
        agentReply(
          calls: [
            agentCall('delegate', 'spawn_subagent', {
              'role': 'reviewer',
              'task': '核对知情边界',
              'background': false,
            }),
          ],
        ),
      ),
    );
    await mainStream.close();
    await childStarted.future;
    final parent = snapshots.values.singleWhere((r) => r.parentId == null);
    expect(parent.steps.last.label, 'spawn_subagent');
    expect(parent.steps.last.isRunning, isTrue);
    expect(parent.steps.last.content, contains('核对知情边界'));
    childStream.add(const LlmEvent(reasoningDelta: '阿弥并不知道钥匙的位置'));
    await childVisible.future;
    runner.cancel();
    expect((await running).status, AgentRunStatus.cancelled);
    final child = store
        .listRuns(workspace.id)
        .singleWhere((r) => r.parentId != null);
    expect(child.steps.last.reasoning, '阿弥并不知道钥匙的位置');
    expect(child.steps.last.isRunning, isFalse);
    expect(child.status, AgentRunStatus.cancelled);
  });
  AgentRuntime runtime(
    FakeAgentClient client, {
    AgentLimits limits = const AgentLimits(),
  }) => AgentRuntime(
    client: client,
    store: store,
    workspace: workspace,
    target: agentTestTarget,
    limits: limits,
    onUpdate: (_) {},
  );

  test('循环执行完整工具并持久化新版本，续接保留前缀且用量只累计每次调用一次', () async {
    final client = FakeAgentClient(
      (request, index) => switch (index) {
        0 => agentReply(
          calls: [
            agentCall('write', 'write_document', {
              'name': '正文',
              'content': '第一稿',
              'expected_revision': 0,
            }),
          ],
          usage: const LlmUsage(
            inputTokens: 100,
            outputTokens: 20,
            cachedInputTokens: 0,
          ),
        ),
        1 => agentReply(
          calls: [
            agentCall('read', 'read_document', {'name': '正文'}),
          ],
        ),
        _ => agentReply(
          text: '第一稿已保存',
          usage: const LlmUsage(
            inputTokens: 150,
            outputTokens: 10,
            cachedInputTokens: 100,
          ),
        ),
      },
    );
    final result = await runtime(client).run('保存一份正文并核实');
    expect(result.status, AgentRunStatus.completed);
    expect(result.content, '第一稿已保存');
    expect(store.readDocument(workspace.id, '正文')?.revision, 1);
    expect(result.usage?.inputTokens, 250);
    expect(result.usage?.outputTokens, 30);
    expect(
      client.requests.last.input.take(client.requests.first.input.length),
      client.requests.first.input,
    );
    expect(client.requests.last.tools, client.requests.first.tools);
    expect(client.controls.map((c) => c.requestId).toSet(), hasLength(3));
    expect(
      store.loadWorkspace(workspace.id)!.history.last,
      isA<LlmAssistantTurn>(),
    );
    expect(
      store.listRuns(workspace.id).single.status,
      AgentRunStatus.completed,
    );
  });

  for (final call in [
    agentCall('unknown', 'shell', {'command': 'whoami'}),
    agentCall('extra', 'write_document', {
      'name': '正文',
      'content': '覆盖',
      'expected_revision': 0,
      'workspace_id': 'other',
    }),
    agentCall('path', 'write_document', {
      'name': '../外部',
      'content': '覆盖',
      'expected_revision': 0,
    }),
    agentCall('type', 'write_document', {
      'name': '正文',
      'content': '覆盖',
      'expected_revision': '0',
    }),
  ]) {
    test('拒绝越权或无效工具参数 ${call.callId}，错误反馈模型且不产生文档', () async {
      final client = FakeAgentClient((request, index) {
        if (index == 0) return agentReply(calls: [call]);
        expect(
          request.input.last,
          isA<LlmToolResult>().having((r) => r.isError, '工具错误', true),
        );
        return agentReply();
      });
      final result = await runtime(client).run('操作文档');
      expect(result.status, AgentRunStatus.completed);
      expect(store.listDocuments(workspace.id), isEmpty);
    });
  }

  test('不完整终态中的工具调用不执行，并明确记录失败', () async {
    final client = FakeAgentClient(
      (_, _) => agentReply(
        stopKind: LlmStopKind.incomplete,
        calls: [
          agentCall('write', 'write_document', {
            'name': '正文',
            'content': '未完成',
            'expected_revision': 0,
          }),
        ],
      ),
    );
    expect((await runtime(client).run('写作')).status, AgentRunStatus.failed);
    expect(store.listDocuments(workspace.id), isEmpty);
    expect(client.requests, hasLength(1));
  });

  test('同步子 Agent 使用独立上下文并拒绝写入与继续派发', () async {
    final client = FakeAgentClient((request, _) {
      final last = request.input.last;
      if (last is LlmTextMessage && last.text == '主任务私有信息') {
        return agentReply(
          calls: [
            agentCall('spawn', 'spawn_subagent', {
              'role': 'writer',
              'task': '仅此子任务',
              'background': false,
            }),
          ],
        );
      }
      if (last is LlmTextMessage && last.text == '仅此子任务') {
        expect(
          request.input.whereType<LlmTextMessage>().map((m) => m.text),
          isNot(contains('主任务私有信息')),
        );
        expect(request.tools.map((t) => t.name), [
          'list_documents',
          'read_document',
        ]);
        return agentReply(
          calls: [
            agentCall('child-write', 'write_document', {
              'name': '越权',
              'content': '内容',
              'expected_revision': 0,
            }),
            agentCall('child-spawn', 'spawn_subagent', {
              'role': 'writer',
              'task': '递归',
              'background': false,
            }),
          ],
        );
      }
      if (last is LlmToolResult && last.callId == 'child-spawn') {
        expect(
          request.input.whereType<LlmToolResult>().every((r) => r.isError),
          isTrue,
        );
        return agentReply(text: '候选正文');
      }
      expect((last as LlmToolResult).output, contains('候选正文'));
      return agentReply(text: '已收到候选正文');
    });
    final result = await runtime(client).run('主任务私有信息');
    expect(result.status, AgentRunStatus.completed);
    expect(store.listDocuments(workspace.id), isEmpty);
    expect(store.listRuns(workspace.id), hasLength(2));
  });

  test('两个后台子任务并行，主任务可先继续，结束前自动收取未读取的结果', () async {
    final childA = Completer<LlmResult>(), childB = Completer<LlmResult>();
    final mainContinued = Completer<void>();
    final client = FakeAgentClient((request, _) {
      final last = request.input.last;
      if (last is LlmTextMessage && last.text == '后台任务') {
        return agentReply(
          calls: [
            agentCall('a', 'spawn_subagent', {
              'role': 'reviewer',
              'task': '子任务甲',
              'background': true,
            }),
            agentCall('b', 'spawn_subagent', {
              'role': 'character',
              'task': '子任务乙',
              'background': true,
            }),
            agentCall('c', 'spawn_subagent', {
              'role': 'writer',
              'task': '超并发',
              'background': true,
            }),
          ],
        );
      }
      if (last is LlmTextMessage && last.text == '子任务甲') return childA.future;
      if (last is LlmTextMessage && last.text == '子任务乙') return childB.future;
      if (last is LlmToolResult) {
        expect(last.isError, isTrue);
        mainContinued.complete();
        return agentReply(text: '提前结束');
      }
      expect(
        (last as LlmTextMessage).text,
        allOf(contains('甲意见'), contains('乙意见')),
      );
      return agentReply(text: '综合意见');
    });
    var finished = false;
    final running = runtime(client).run('后台任务').then((r) {
      finished = true;
      return r;
    });
    await mainContinued.future;
    expect(finished, isFalse);
    childA.complete(agentReply(text: '甲意见'));
    childB.complete(agentReply(text: '乙意见'));
    expect((await running).content, '综合意见');
    expect(
      store
          .listRuns(workspace.id)
          .every((r) => r.status == AgentRunStatus.completed),
      isTrue,
    );
  });

  test('停止主任务会取消等待中的子调用，补齐工具结果且后续任务不重放旧工具', () async {
    final childStarted = Completer<void>(), childReply = Completer<LlmResult>();
    final client = FakeAgentClient((request, _) {
      if (request.input.last case LlmTextMessage(text: '等候子任务')) {
        return agentReply(
          calls: [
            agentCall('s', 'spawn_subagent', {
              'role': 'writer',
              'task': '等待',
              'background': false,
            }),
          ],
        );
      }
      childStarted.complete();
      return childReply.future;
    });
    final engine = runtime(client);
    final running = engine.run('等候子任务');
    await childStarted.future;
    engine.cancel();
    expect((await running).status, AgentRunStatus.cancelled);
    expect(client.controls.every((c) => c.isCancelled), isTrue);
    expect(
      store
          .listRuns(workspace.id)
          .every((r) => r.status != AgentRunStatus.running),
      isTrue,
    );
    final history = store.loadWorkspace(workspace.id)!.history;
    expect(history.whereType<LlmToolResult>(), hasLength(1));
    // 解除测试生成器的等待，验证迟到结果不会覆盖取消终态。
    childReply.complete(agentReply(text: '迟到正文'));
    workspace = store.loadWorkspace(workspace.id)!;
    final nextClient = FakeAgentClient((_, _) => agentReply(text: '继续完成'));
    expect(
      (await runtime(nextClient).run('继续')).status,
      AgentRunStatus.completed,
    );
    expect(nextClient.requests, hasLength(1));
    expect(store.listDocuments(workspace.id), isEmpty);
  });

  test('全树模型预算阻止继续请求，已完成的文档保存仍可读取', () async {
    final client = FakeAgentClient(
      (_, _) => agentReply(
        calls: [
          agentCall('w', 'write_document', {
            'name': '正文',
            'content': '保留的草稿',
            'expected_revision': 0,
          }),
        ],
      ),
    );
    final result = await runtime(
      client,
      limits: const AgentLimits(totalModelCalls: 1),
    ).run('反复写作');
    expect(result.status, AgentRunStatus.limitReached);
    expect(client.requests, hasLength(1));
    expect(store.readDocument(workspace.id, '正文')?.content, '保留的草稿');
  });

  test('收取工具只能访问当前主任务的子任务，不能用任意任务 ID 越权', () async {
    final client = FakeAgentClient((request, index) {
      if (index == 0) {
        return agentReply(
          calls: [
            agentCall('c', 'collect_subagent', {
              'task_id': 'other-root-task',
              'wait': true,
            }),
          ],
        );
      }
      expect(
        jsonDecode((request.input.last as LlmToolResult).output)['error'],
        contains('不属于'),
      );
      return agentReply();
    });
    expect(
      (await runtime(client).run('收取任务')).status,
      AgentRunStatus.completed,
    );
  });

  test('后台启动返回任务 ID，显式收取等待同一子任务结果而不重复调用', () async {
    final childReply = Completer<LlmResult>(), collecting = Completer<void>();
    final client = FakeAgentClient((request, _) {
      final last = request.input.last;
      if (last is LlmTextMessage && last.text == '启动后收取') {
        return agentReply(
          calls: [
            agentCall('s', 'spawn_subagent', {
              'role': 'reviewer',
              'task': '后台审稿',
              'background': true,
            }),
          ],
        );
      }
      if (last is LlmTextMessage && last.text == '后台审稿') {
        return childReply.future;
      }
      if (last is LlmToolResult && last.callId == 's') {
        collecting.complete();
        return agentReply(
          calls: [
            agentCall('c', 'collect_subagent', {
              'task_id': jsonDecode(last.output)['task_id'],
              'wait': true,
            }),
          ],
        );
      }
      expect((last as LlmToolResult).output, contains('审稿完成'));
      return agentReply(text: '已综合审稿');
    });
    var finished = false;
    final running = runtime(client).run('启动后收取').then((r) {
      finished = true;
      return r;
    });
    await collecting.future;
    expect(finished, isFalse);
    childReply.complete(agentReply(text: '审稿完成'));
    expect((await running).content, '已综合审稿');
    expect(store.listRuns(workspace.id), hasLength(2));
    expect(client.requests, hasLength(4));
  });

  test('子 Agent 的调用也消耗主任务全树预算', () async {
    final client = FakeAgentClient((request, _) {
      if (request.input.last case LlmTextMessage(text: '预算内委派')) {
        return agentReply(
          calls: [
            agentCall('s', 'spawn_subagent', {
              'role': 'writer',
              'task': '子任务',
              'background': false,
            }),
          ],
        );
      }
      return agentReply(text: '子任务完成');
    });
    final result = await runtime(
      client,
      limits: const AgentLimits(totalModelCalls: 2),
    ).run('预算内委派');
    expect(result.status, AgentRunStatus.limitReached);
    expect(client.requests, hasLength(2));
    expect(
      store.listRuns(workspace.id).firstWhere((r) => r.parentId != null).status,
      AgentRunStatus.completed,
    );
  });
}
