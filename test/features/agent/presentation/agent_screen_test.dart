import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/composition/llm_bindings.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/application/agent_runtime.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_screen.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_run_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';
import '../agent_test_helpers.dart';

void main() {
  testWidgets('子 Agent 运行时可以进入完整执行流，返回主会话后继续接收结果', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '雾港', modelId: 'model-1'),
    );
    store.writeDocument('novel', '设定', '阿弥不知道钥匙的位置。', expectedRevision: 0);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.model()],
    );
    final release = Completer<void>(), childStarted = Completer<void>();
    final client = StreamingAgentClient((_, index) async* {
      if (index == 0) {
        yield LlmCompleted(
          agentReply(
            calls: [
              agentCall('s', 'spawn_subagent', {
                'role': 'reviewer',
                'task': '核对阿弥的知情边界，保留完整依据。',
                'background': false,
              }),
            ],
          ),
        );
      } else if (index == 1) {
        yield LlmCompleted(
          agentReply(
            calls: [
              agentCall('r', 'read_document', {'name': '设定'}),
            ],
          ),
        );
      } else if (index == 2) {
        childStarted.complete();
        yield const LlmEvent(reasoningDelta: '正在逐项核对角色已经知道的事情。');
        await release.future;
        yield LlmCompleted(agentReply(text: '子任务核对完成。'));
      } else {
        yield LlmCompleted(agentReply(text: '主任务已采纳审稿结果。'));
      }
    });
    final router = createAppRouter(
      initialLocation: '/agent',
      videoPlayerBindingsFactory: () => throw UnimplementedError(),
    );
    addTearDown(router.dispose);
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      router: router,
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentScreen)),
    );
    final visible = Completer<void>(), finished = Completer<void>();
    final subscription = container.listen(agentWorkspaceProvider, (_, state) {
      if (state.runs.any(
            (r) =>
                r.parentId != null &&
                r.steps.any((s) => s.reasoning.isNotEmpty),
          ) &&
          !visible.isCompleted) {
        visible.complete();
      }
      if (state.runs.any(
            (r) => r.parentId == null && r.status == AgentRunStatus.completed,
          ) &&
          !state.busy &&
          !finished.isCompleted) {
        finished.complete();
      }
    });
    addTearDown(subscription.close);
    await tester.enterText(find.widgetWithText(TextField, '任务'), '请委派审稿');
    await tester.pump();
    await tester.tap(find.text('开始任务'));
    await tester.runAsync(() => childStarted.future);
    // 网络事件已到达，只推进 UI 输出合并的计时器。
    await tester.pump(AgentRuntime.streamRefreshInterval);
    expect(visible.isCompleted, isTrue);
    await tester.tap(find.textContaining('审稿 Agent ·').first);
    await settleOverlayTransition(tester);
    expect(find.byType(AgentRunScreen), findsOneWidget);
    expect(find.text('核对阿弥的知情边界，保留完整依据。'), findsOneWidget);
    expect(find.text('正在逐项核对角色已经知道的事情。'), findsOneWidget);
    await tester.tap(find.text('read_document'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('阿弥不知道钥匙的位置。'), findsOneWidget);
    expect(container.read(agentWorkspaceProvider).busy, isTrue);
    await tester.tap(find.text('返回主 Agent'));
    await settleOverlayTransition(tester);
    expect(find.byType(AgentScreen), findsOneWidget);
    release.complete();
    await tester.runAsync(() => finished.future);
    await tester.pump();
    expect(find.text('主任务已采纳审稿结果。'), findsOneWidget);
    expect(
      store
          .listRuns('novel')
          .every((r) => r.status == AgentRunStatus.completed),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立路由运行任务后展示结果，可编辑正文并查看旧版本', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说工作区', modelId: 'model-1'),
    );
    store.writeDocument('novel', '正文', '旧稿', expectedRevision: 0);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.model()],
    );
    final client = FakeAgentClient(
      (_, _) => agentReply(text: '**审阅完成，建议调整结尾。**'),
    );
    final router = createAppRouter(
      initialLocation: '/agent',
      videoPlayerBindingsFactory: () => throw UnimplementedError(),
    );
    addTearDown(router.dispose);
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      router: router,
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
    );
    expect(find.text('Agent 工作区'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '任务'), '审阅正文');
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentScreen)),
    );
    final completed = Completer<void>();
    final subscription = container.listen(agentWorkspaceProvider, (_, next) {
      if (next.runs.any((r) => r.status == AgentRunStatus.completed) &&
          !next.busy &&
          !completed.isCompleted) {
        completed.complete();
      }
    });
    addTearDown(subscription.close);
    await tester.tap(find.text('开始任务'));
    await tester.runAsync(() => completed.future);
    await tester.pump();
    expect(find.text('审阅完成，建议调整结尾。'), findsOneWidget);
    expect(store.listRuns('novel').single.status, AgentRunStatus.completed);
    await tester.tap(find.byTooltip('工作文档'));
    await settleTabTransition(tester);
    await tester.tap(find.text('正文'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '旧稿'), '修订稿');
    await tester.tap(find.text('保存新版本'));
    await settleOverlayTransition(tester);
    expect(find.text('版本 2 · 3 字符'), findsOneWidget);
    await tester.tap(find.text('正文'));
    await settleOverlayTransition(tester);
    await tester.tap(find.byTooltip('上一版本'));
    await tester.pump();
    expect(find.text('旧稿'), findsOneWidget);
    expect(store.readDocument('novel', '正文')?.content, '修订稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏键盘弹出仍可提交和停止全部任务', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '工作区', modelId: 'model-1'),
    );
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.model()],
    );
    final started = Completer<void>(), reply = Completer<LlmResult>();
    final client = FakeAgentClient((_, _) {
      started.complete();
      return reply.future;
    });
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      child: const AgentScreen(),
      viewportSize: const Size(390, 844),
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
    );
    const task = '继续写作\n读取设定\n检查动机\n审查对白\n保存正文';
    await tester.enterText(find.widgetWithText(TextField, '任务'), task);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentScreen)),
    );
    final stopped = Completer<void>();
    final subscription = container.listen(agentWorkspaceProvider, (_, next) {
      if (!next.busy &&
          next.runs.any((r) => r.status == AgentRunStatus.cancelled) &&
          !stopped.isCompleted) {
        stopped.complete();
      }
    });
    addTearDown(subscription.close);
    await tester.tap(find.text('开始任务'));
    await tester.runAsync(() => started.future);
    await tester.pump();
    await tester.tap(find.text('停止全部'));
    await tester.runAsync(() => stopped.future);
    await tester.pump();
    expect(find.text('已停止'), findsOneWidget);
    expect(find.text(task), findsOneWidget);
    expect(client.controls.single.isCancelled, isTrue);
    reply.complete(agentReply(text: '迟到'));
    expect(tester.takeException(), isNull);
  });
}
