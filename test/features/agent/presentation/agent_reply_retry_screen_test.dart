import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/app/composition/llm_bindings.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';
import '../agent_test_helpers.dart';

void main() {
  testWidgets('最新回复重试需确认且运行中不可重复提交，取消不改变消息', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    final before = AgentWorkspace(id: 'novel', title: '作品', modelId: 'model-1');
    store.saveWorkspace(before);
    for (var i = 0; i < 2; i++) {
      store.checkpoint(
        AgentRunRecord(
          id: 'run-$i',
          workspaceId: 'novel',
          prompt: '指令 $i',
          startedAt: DateTime(2026).add(Duration(seconds: i)),
          content: '回复 $i',
          status: AgentRunStatus.completed,
          recovery: AgentRunRecovery(beforeWorkspace: before),
        ),
      );
    }
    final started = Completer<void>(), reply = Completer<LlmResult>();
    final client = FakeAgentClient((_, _) {
      started.complete();
      return reply.future;
    });
    await pumpTestApp(
      tester,
      preferences: await TestFixtures.seedPreferences(
        database: database,
        models: [TestFixtures.model()],
      ),
      database: database,
      child: const AgentScreen(),
      viewportSize: const Size(430, 1100),
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
    );
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('不保留版本'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(client.requests, isEmpty);
    expect(store.loadRun('novel', 'run-1')!.content, '回复 1');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentScreen)),
    );
    final finished = Completer<void>();
    final subscription = container.listen(agentWorkspaceProvider, (_, state) {
      if (!state.busy &&
          state.runs.any((r) => r.content == '新回复') &&
          !finished.isCompleted) {
        finished.complete();
      }
    });
    addTearDown(subscription.close);
    await tester.tap(find.text('重试'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('重试并覆盖'));
    await tester.runAsync(
      () => started.future.timeout(const Duration(seconds: 10)),
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('重试最新回复？'), findsNothing);
    expect(client.requests, hasLength(1));
    reply.complete(agentReply(text: '新回复'));
    await tester.runAsync(
      () => finished.future.timeout(const Duration(seconds: 10)),
    );
    await tester.pump();
    expect(find.textContaining('新回复', findRichText: true), findsWidgets);
    expect(store.listRuns('novel'), hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
