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
import 'package:oh_my_llm/features/agent/presentation/agent_document_editor.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';
import '../agent_test_helpers.dart';

void main() {
  testWidgets('侧栏搜索重命名和切换作品保留各作品草稿', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    for (var i = 1; i <= 35; i++) {
      store.saveWorkspace(AgentWorkspace(id: 'novel-$i', title: '作品 $i'));
    }
    final selected = store.loadWorkspace('novel-1')!;
    store.saveWorkspace(selected.copyWith(draft: '开场草稿'));
    store.saveWorkspace(
      store.loadWorkspace('novel-2')!.copyWith(draft: '后续草稿'),
    );
    await pumpTestApp(
      tester,
      preferences: await TestFixtures.seedPreferences(database: database),
      database: database,
      child: const AgentScreen(),
    );
    await tester.tap(find.byTooltip('打开侧边内容'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '搜索作品'), '作品 1');
    await tester.pump();
    await tester.tap(find.byTooltip('重命名作品「作品 1」'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '作品名称'), '雾港');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '搜索作品'), '雾港');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, '雾港'));
    await tester.pump();
    await settleOverlayTransition(tester);
    expect(find.text('开场草稿'), findsOneWidget);
    expect(find.text('新建会话'), findsNothing);
    expect(store.loadWorkspace('novel-2')!.draft, '后续草稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建世界书并在同一作品应用独立审稿模型方案和查看输入', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '配置试验', modelId: 'model-1'),
    );
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [
        TestFixtures.model(providerName: '测试商', displayName: '写作模型'),
        TestFixtures.model(
          id: 'model-2',
          providerName: '测试商',
          displayName: '审稿模型',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      child: const AgentScreen(),
      viewportSize: const Size(780, 1000),
    );
    await tester.tap(find.byTooltip('工作文档'));
    await tester.pump();
    await tester.tap(find.text('新建文档'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '文档名'), '世界规则');
    await tester.tap(find.byType(DropdownButtonFormField<AgentDocumentKind>));
    await settleOverlayTransition(tester);
    await tester.tap(
      find.text(agentDocumentKindLabel(AgentDocumentKind.worldBook)).last,
    );
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '正文'), '日落后禁止出城。');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(find.text('世界书 1'), findsOneWidget);
    await tester.tap(find.byTooltip('模型与规则'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('不兼容的推理、签名'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '方案名称'), '独立审稿方案');
    await tester.tap(find.byType(DropdownButtonFormField<AgentRole>));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('审稿 Agent').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('测试商 / 审稿模型').last);
    await settleOverlayTransition(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '角色提示词'),
      '只报告有原文依据的矛盾。',
    );
    await tester.tap(find.text('保存方案'));
    await tester.pump();
    expect(store.listConfigurations('novel').single.name, '独立审稿方案');
    await tester.tap(find.text('应用配置'));
    await settleOverlayTransition(tester);
    final saved = store.loadWorkspace('novel')!;
    expect(saved.configuration.name, '独立审稿方案');
    expect(saved.configuration.modelFor(AgentRole.reviewer), 'model-2');
    await tester.tap(find.byTooltip('返回执行流'));
    await tester.pump();
    await tester.tap(find.byTooltip('查看上下文'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('日落后禁止出城。'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    expect(find.text('新建会话'), findsNothing);
    expect(store.listWorkspaces(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('子 Agent 运行时可以进入完整执行流，返回主会话后继续接收结果', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '雾港', modelId: 'model-1'),
    );
    store.writeDocument('novel', '设定', '阿弥不知道钥匙的位置。');
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
    await tester.tap(find.textContaining('read_document ·'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('阿弥不知道钥匙的位置。'), findsOneWidget);
    expect(container.read(agentWorkspaceProvider).busy, isTrue);
    await tester.tap(find.text('返回上级任务'));
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

  testWidgets('独立路由运行任务后展示结果，编辑正文直接覆盖当前内容', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说工作区', modelId: 'model-1'),
    );
    store.writeDocument('novel', '正文', '旧稿');
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
    expect(find.text('Agent 小说工作区'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(ListTile, '正文'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '旧稿'), '修订稿');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(find.text('普通文档 · 3 字符'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '正文'));
    await settleOverlayTransition(tester);
    expect(find.byTooltip('上一版本'), findsNothing);
    expect(find.widgetWithText(TextField, '修订稿'), findsOneWidget);
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
    await tester.tap(find.byTooltip('工作文档'));
    await tester.pump();
    expect(find.text('停止'), findsOneWidget);
    await tester.tap(find.byTooltip('剧情状态与正文'));
    await tester.pump();
    expect(find.text('停止'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回执行流'));
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
