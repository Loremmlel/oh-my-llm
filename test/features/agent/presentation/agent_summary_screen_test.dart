import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/composition/llm_bindings.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_context_batch.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_summary_dialog.dart';

import '../../../helpers/async/widget_test_animation.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/fixtures.dart';
import '../agent_story_test_helpers.dart';
import '../agent_test_helpers.dart';

void main() {
  testWidgets('窄屏窗口恢复和编辑累计摘要，键盘弹出仍可保存且取消保护未保存内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final store = SqliteAgentStore(db);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '小说'));
    seedProseFloor(store, 1);
    store.saveContextBatch(
      'novel',
      AgentContextBatch(
        id: 'saved',
        roundIds: ['floor-1'],
        historyEnd: 1,
        summary: '初始累计摘要',
      ),
    );
    await pumpTestApp(
      tester,
      database: db,
      preferences: await TestFixtures.seedPreferences(
        database: db,
        models: [
          TestFixtures.model(
            apiUrl: agentTestTarget.endpoint,
            modelName: agentTestTarget.model,
          ),
        ],
      ),
      viewportSize: const Size(390, 844),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAgentSummaries(context),
            child: const Text('打开总结'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开总结'));
    await settleOverlayTransition(tester);
    expect(find.text('直接隐藏'), findsNothing);
    expect(store.listContextBatches('novel').single.active, isTrue);
    await tester.ensureVisible(find.text('编辑摘要'));
    await tester.tap(find.text('编辑摘要'));
    await settleOverlayTransition(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '摘要'), '窗口内的摘要');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    tester.view.resetViewInsets();
    await settleAnimatedWidgetTransition(tester);
    expect(store.listContextBatches('novel').single.summary, '窗口内的摘要');
    await tester.ensureVisible(find.text('恢复全部原文'));
    await tester.tap(find.text('恢复全部原文'));
    await tester.pump();
    expect(
      store.listContextBatches('novel').single.status,
      AgentContextBatchStatus.restored,
    );
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    expect(find.text('窗口内的摘要'), findsNothing);
  });

  testWidgets('关闭总结窗口不会停止，重新打开后可停止并重试且不改主对话', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final store = SqliteAgentStore(db);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '小说', modelId: 'model-1'),
    );
    seedProseFloor(store, 1);
    final history = store.loadWorkspace('novel')!.history;
    final entered = Completer<void>(), release = Completer<void>();
    final client = FakeAgentClient((_, index) async {
      if (index == 0) {
        entered.complete();
        await release.future;
      }
      return agentReply(text: '正式摘要');
    });
    await pumpTestApp(
      tester,
      database: db,
      preferences: await TestFixtures.seedPreferences(
        database: db,
        models: [
          TestFixtures.model(
            apiUrl: agentTestTarget.endpoint,
            modelName: agentTestTarget.model,
          ),
        ],
      ),
      viewportSize: const Size(390, 844),
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAgentSummaries(context),
            child: const Text('打开总结'),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('打开总结')),
    );
    await tester.tap(find.text('打开总结'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('压缩并替代'));
    await tester.runAsync(
      () => entered.future.timeout(const Duration(seconds: 5)),
    );
    await tester.pump();
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    expect(container.read(agentWorkspaceProvider).busy, isTrue);
    await tester.tap(find.text('打开总结'));
    await settleOverlayTransition(tester);
    final done = Completer<void>();
    final sub = container.listen(agentWorkspaceProvider, (_, next) {
      if (!next.busy && !done.isCompleted) done.complete();
    });
    await tester.tap(find.text('停止'));
    await tester.runAsync(
      () => done.future.timeout(const Duration(seconds: 5)),
    );
    sub.close();
    release.complete();
    await tester.pump();
    expect(store.listContextBatches('novel'), isEmpty);
    await tester.ensureVisible(find.text('重试总结'));
    final retried = container
        .read(agentWorkspaceProvider.notifier)
        .retrySummaryBatch!;
    await tester.runAsync(
      () => container
          .read(agentWorkspaceProvider.notifier)
          .send(summaryBatch: retried),
    );
    await tester.pump();
    expect(store.listContextBatches('novel').single.summary, '正式摘要');
    expect(store.loadWorkspace('novel')!.history, history);
    expect(tester.takeException(), isNull);
  });
}
