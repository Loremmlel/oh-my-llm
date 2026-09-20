import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/composition/llm_bindings.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_screen.dart';

import '../../../helpers/async/widget_test_animation.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../agent_test_helpers.dart';
import '../agent_story_test_helpers.dart';

void main() {
  testWidgets('窄屏可重试状态更新、查看正文和状态，并用键盘撤回恢复原指令', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(
      AgentWorkspace(id: 'novel', title: '图书馆', modelId: 'model-1'),
    );
    // 失败转移由 controller 测试覆盖；页面从已有待处理轮次验证重试与撤回入口。
    final round = prepareRound(store, '开场', content: '甲把秘密留在心里。');
    for (final id in [round.id, round.stateAgentId]) {
      store.checkpoint(
        store.loadRun('novel', id)!.copyWith(status: AgentRunStatus.failed),
      );
    }
    store.saveDraft('novel', '');
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [
        TestFixtures.model(
          apiUrl: agentTestTarget.endpoint,
          modelName: agentTestTarget.model,
        ),
      ],
    );
    final client = FakeAgentClient(
      (_, _) => agentReply(
        calls: [
          agentCall('commit', 'commit_story_state', {
            'operations': [
              AgentStateOperation(
                kind: AgentStateOperationKind.insert,
                table: AgentStateTable.scene,
                cells: {'place': '图书馆', 'time': '傍晚'},
              ).toJson(),
            ],
          }),
        ],
      ),
    );
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      viewportSize: const Size(390, 844),
      child: const AgentScreen(),
      extraOverrides: [llmClientProvider.overrideWithValue(client)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentScreen)),
    );
    final saved = Completer<void>();
    final subscription = container.listen(agentWorkspaceProvider, (_, state) {
      if (!state.busy &&
          state.latestRound?.status == AgentStoryRoundStatus.committed &&
          !saved.isCompleted) {
        saved.complete();
      }
    });
    addTearDown(subscription.close);
    expect(find.text('正文已保留 · 状态待更新'), findsOneWidget);
    await tester.tap(find.text('重试状态更新'));
    await tester.runAsync(
      () => saved.future.timeout(const Duration(seconds: 10)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('剧情状态与正文'));
    await tester.pump();
    expect(find.text('地点：图书馆'), findsOneWidget);
    await tester.tap(find.widgetWithText(ExpansionTile, '正文'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.textContaining('甲把秘密留在心里。', findRichText: true), findsWidgets);
    await tester.tap(find.byTooltip('返回执行流'));
    await tester.pump();
    // 通过 Material 按钮的焦点与键盘激活验证撤回，不依赖屏幕坐标。
    final button = find.widgetWithText(TextButton, '撤回最新一轮');
    Focus.of(
      tester.element(
        find.descendant(of: button, matching: find.text('撤回最新一轮')),
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.widgetWithText(TextField, round.beforeWorkspace.draft),
      findsOneWidget,
    );
    expect(find.text('撤回最新一轮'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
