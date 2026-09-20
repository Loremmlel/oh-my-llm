import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/application/agent_model.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

import '../agent_test_helpers.dart';

void main() {
  late AppDatabase database;
  late SqliteAgentStore store;
  setUp(() {
    database = AppDatabase.inMemory();
    store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', modelId: 'main'),
    );
  });
  tearDown(() => database.close());

  test('主 Agent 改稿后独立状态模型只接收最终版本，保存后可恢复原上下文并回看实际输入', () async {
    final stateTarget = LlmRequestTarget(
      protocol: agentTestTarget.protocol,
      endpoint: agentTestTarget.endpoint,
      apiKey: 'state-key',
      model: 'state-model',
    );
    final client = reviewedAgentClient((request, index) {
      if (request.target.model == 'state-model') {
        final input = agentInputText(request.input);
        expect(input, contains('甲最终没有告诉乙秘密'));
        expect(input, isNot(contains('废稿：乙已经知道秘密')));
        expect(request.tools.map((t) => t.name), [
          'read_story_state',
          'commit_story_state',
        ]);
        return agentReply(
          target: request.target,
          calls: [
            agentCall('commit', 'commit_story_state', {
              'operations': [
                AgentStateOperation(
                  kind: AgentStateOperationKind.insert,
                  table: AgentStateTable.characters,
                  cells: {'name': '乙', 'knowledge': '不知道秘密'},
                ).toJson(),
              ],
            }),
          ],
        );
      }
      return switch (index) {
        0 => agentReply(
          calls: [
            agentCall('draft', 'write_document', {
              'name': '正文',
              'content': '废稿：乙已经知道秘密',
            }),
          ],
        ),
        1 => agentReply(
          calls: [
            agentCall('final', 'write_document', {
              'name': '正文',
              'content': '甲最终没有告诉乙秘密',
            }),
          ],
        ),
        2 => agentReply(
          calls: [
            agentCall('update', 'update_story_state', {'name': '正文'}),
          ],
        ),
        _ => agentReply(text: '本轮已完成'),
      };
    });
    final runtime = AgentRuntime(
      client: client,
      store: store,
      workspace: store.loadWorkspace('novel')!,
      roleModels: {
        AgentRole.coordinator: const AgentModel(
          id: 'main',
          label: '主模型',
          target: agentTestTarget,
          options: LlmGenerationOptions(),
        ),
        AgentRole.reviewer: const AgentModel(
          id: 'main',
          label: '审查模型',
          target: agentTestTarget,
          options: LlmGenerationOptions(),
        ),
        AgentRole.state: AgentModel(
          id: 'state',
          label: '状态模型',
          target: stateTarget,
          options: const LlmGenerationOptions(),
        ),
      },
      onUpdate: (_) {},
    );
    final result = await runtime.run('开场：甲乙来到图书馆');
    expect(result.status, AgentRunStatus.completed);
    expect(client.requests, hasLength(5));
    expect(result.content, '甲最终没有告诉乙秘密');
    expect(
      store.readStoryState('novel').rows.single.cells['knowledge'],
      '不知道秘密',
    );
    final round = store.latestStoryRound('novel')!;
    final input = result.inputHistory!;
    store.withdrawStoryRound('novel', round.id);
    expect(store.loadWorkspace('novel')!.history, isEmpty);
    expect(store.loadWorkspace('novel')!.draft, '开场：甲乙来到图书馆');
    expect(store.listDocuments('novel'), isEmpty);
    expect(store.readDocument('novel', '正文'), isNull);
    final archived = store.loadRun('novel', result.id)!;
    expect(archived.inputHistory, input);
    expect(
      archived.inputHistory!.take(
        result.steps
            .where((s) => s.kind == AgentStepKind.model)
            .last
            .inputItemCount!,
      ),
      client.requests[2].input,
    );
  });

  test('状态 Agent 越权工具被拒绝，未提交不能作为成功完成', () async {
    var stateCalls = 0;
    final client = reviewedAgentClient((request, index) {
      if (request.tools.any((t) => t.name == 'commit_story_state')) {
        if (stateCalls++ == 0) {
          return agentReply(
            calls: [
              agentCall('denied', 'write_document', {
                'name': '正文',
                'content': '越权改稿',
              }),
            ],
          );
        }
        expect(request.input.whereType<LlmToolResult>().last.isError, isTrue);
        return agentReply(text: '没有提交却声称完成');
      }
      return switch (index) {
        0 => agentReply(
          calls: [
            agentCall('write', 'write_document', {
              'name': '正文',
              'content': '正式正文',
            }),
          ],
        ),
        1 => agentReply(
          calls: [
            agentCall('update', 'update_story_state', {'name': '正文'}),
          ],
        ),
        _ => agentReply(text: '结束'),
      };
    });
    final runtime = AgentRuntime(
      client: client,
      store: store,
      workspace: store.loadWorkspace('novel')!,
      roleModels: agentTestModels,
      onUpdate: (_) {},
    );
    final result = await runtime.run('写作');
    expect(result.status, AgentRunStatus.failed);
    expect(
      store.latestStoryRound('novel')!.status,
      AgentStoryRoundStatus.pending,
    );
    expect(store.readDocument('novel', '正文')!.content, '正式正文');
    expect(store.readStoryState('novel').rows, isEmpty);
  });

  for (final afterCommit in [false, true]) {
    test('状态${afterCommit ? '提交后' : '调用中'}停止时保留正确的持久终态', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      late AgentRuntime runtime;
      final client = reviewedAgentClient((request, index) async {
        if (request.tools.any((t) => t.name == 'commit_story_state')) {
          entered.complete();
          if (!afterCommit) await release.future;
          return agentReply(
            calls: [
              agentCall('commit', 'commit_story_state', {'operations': []}),
            ],
          );
        }
        return index == 0
            ? agentReply(
                calls: [
                  agentCall('write', 'write_document', {
                    'name': '正文',
                    'content': '已审查正文',
                  }),
                ],
              )
            : agentReply(
                calls: [
                  agentCall('update', 'update_story_state', {'name': '正文'}),
                ],
              );
      });
      runtime = AgentRuntime(
        client: client,
        store: store,
        workspace: store.loadWorkspace('novel')!,
        roleModels: agentTestModels,
        onUpdate: (record) {
          if (afterCommit &&
              record.role == AgentRole.state &&
              store.latestStoryRound('novel')?.status ==
                  AgentStoryRoundStatus.committed) {
            runtime.cancel();
          }
        },
      );
      final running = runtime.run('写作');
      await entered.future;
      if (!afterCommit) runtime.cancel();
      final result = await running;
      if (!afterCommit) release.complete();
      expect(
        result.status,
        afterCommit ? AgentRunStatus.completed : AgentRunStatus.cancelled,
      );
      expect(
        store.latestStoryRound('novel')!.status,
        afterCommit
            ? AgentStoryRoundStatus.committed
            : AgentStoryRoundStatus.pending,
      );
      expect(store.readStoryState('novel').revision, afterCommit ? 1 : 0);
    });
  }

  test('子任务预算不足仍保存待处理轮次，后续普通任务被阻止', () async {
    final client = reviewedAgentClient(
      (_, index) => switch (index) {
        0 => agentReply(
          calls: [
            agentCall('write', 'write_document', {
              'name': '正文',
              'content': '正式正文',
            }),
          ],
        ),
        1 => agentReply(
          calls: [
            agentCall('update', 'update_story_state', {'name': '正文'}),
          ],
        ),
        _ => agentReply(text: '预算不足'),
      },
    );
    final runtime = AgentRuntime(
      client: client,
      store: store,
      workspace: store.loadWorkspace('novel')!,
      roleModels: agentTestModels,
      limits: const AgentLimits(children: 1),
      onUpdate: (_) {},
    );
    final result = await runtime.run('开场');
    expect(result.status, AgentRunStatus.failed);
    expect(
      store.latestStoryRound('novel')!.status,
      AgentStoryRoundStatus.pending,
    );
    final next = AgentRuntime(
      client: client,
      store: store,
      workspace: store.loadWorkspace('novel')!,
      roleModels: agentTestModels,
      onUpdate: (_) {},
    );
    await expectLater(next.run('下一轮'), throwsA(isA<AgentWorkspaceException>()));
    expect(
      jsonEncode(store.readStoryState('novel').toJson()),
      isNot(contains('正式正文')),
    );
  });
}
