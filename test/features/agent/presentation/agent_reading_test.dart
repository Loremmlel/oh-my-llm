import 'dart:convert';

import 'package:oh_my_llm/core/widgets/app_text_field.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_document_editor.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_transcript.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('已完成模型步骤按需展开且采用正文始终可读', (tester) async {
    final workspace = AgentWorkspace(id: 'w', title: '作品');
    final record = AgentRunRecord(
      id: 'r',
      workspaceId: 'w',
      prompt: '继续写作',
      startedAt: DateTime(2026),
      status: AgentRunStatus.completed,
      steps: const [
        AgentStep(
          label: '撰写正文',
          content: '中间候选稿',
          usage: LlmUsage(
            inputTokens: 100,
            outputTokens: 30,
            outputDuration: Duration(seconds: 2),
          ),
        ),
      ],
    );
    final round = AgentStoryRound(
      id: 'r',
      beforeWorkspace: workspace,
      document: const AgentDocument(name: '第一章', content: '正式采用正文'),
      beforeState: AgentStoryState(),
      stateAgentId: 's',
      status: AgentStoryRoundStatus.committed,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentTranscript(
            records: [record],
            allRuns: [record],
            storyRounds: [round],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('展开执行过程 · 1 步'));
    await tester.pump();
    expect(find.text('中间候选稿'), findsNothing);
    expect(find.text('正式采用正文'), findsOneWidget);
    await tester.tap(find.text('撰写正文'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.text('中间候选稿'), findsOneWidget);
    expect(find.text('· TPS 15.0'), findsOneWidget);
    expect(find.text('正式采用正文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文选定后自动折叠整轮过程，仍可展开诊断与查看失败', (tester) async {
    final workspace = AgentWorkspace(id: 'w', title: '南川一中');
    final running = AgentRunRecord(
      id: 'r',
      workspaceId: 'w',
      prompt: '开始写作',
      startedAt: DateTime(2026),
      steps: [
        const AgentStep(label: '模型回复 1', content: '中间讨论与候选稿'),
        AgentStep(
          label: 'write_document',
          kind: AgentStepKind.tool,
          content: jsonEncode({
            'arguments': {'name': '第一段', 'content': '候选稿'},
          }),
        ),
      ],
    );
    final round = AgentStoryRound(
      id: 'r',
      beforeWorkspace: workspace,
      document: const AgentDocument(
        name: '第一段',
        content: '雨水顺着窗沿落下，林知夏打开了蓝色素材本。',
      ),
      beforeState: AgentStoryState(),
      stateAgentId: 's',
    );
    Widget page(AgentRunRecord record, List<AgentStoryRound> rounds) =>
        MaterialApp(
          home: Scaffold(
            body: AgentTranscript(
              records: [record],
              allRuns: [record],
              storyRounds: rounds,
            ),
          ),
        );
    await tester.pumpWidget(page(running, []));
    await tester.pump();
    expect(find.text('中间讨论与候选稿'), findsOneWidget);
    await tester.pumpWidget(page(running, [round]));
    await tester.pump();
    expect(find.text('中间讨论与候选稿'), findsNothing);
    expect(find.text(round.document.content), findsOneWidget);
    expect(find.text('正文已选定，剧情状态待更新。'), findsOneWidget);
    await tester.tap(find.text('展开执行过程 · 2 步'));
    await tester.pump();
    expect(find.text('中间讨论与候选稿'), findsOneWidget);
    await tester.pumpWidget(
      page(running.copyWith(status: AgentRunStatus.failed, error: '状态更新失败'), [
        round,
      ]),
    );
    await tester.pump();
    expect(find.text('中间讨论与候选稿'), findsNothing);
    expect(find.text('状态更新失败'), findsOneWidget);
    expect(find.text(round.document.content), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏文档显示归一化换行，取消不改原文且滚动和键盘弹出后可保存', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    store.saveWorkspace(AgentWorkspace(id: 'w', title: '南川一中'));
    final document = store.writeDocument(
      'w',
      '世界书',
      List.filled(100, '校园设定').join('\r\n'),
      kind: AgentDocumentKind.worldBook,
    );
    final preferences = await TestFixtures.seedPreferences(database: database);
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      viewportSize: const Size(390, 844),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAgentDocumentEditor(context, document: document),
            child: const Text('编辑'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    final name = find.widgetWithText(AppTextField, '文档名');
    final body = find.widgetWithText(AppTextField, '正文');
    expect(
      tester.widget<AppTextField>(body).controller!.text,
      List.filled(100, '校园设定').join('\n'),
    );
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('编辑文档'), findsNothing);
    expect(store.readDocument('w', '世界书'), document);

    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    await tester.drag(body, const Offset(0, -180));
    await tester.pump();
    expect(name.hitTestable(), findsOneWidget);
    expect(find.text('保存').hitTestable(), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await settleOverlayTransition(tester);
    expect(find.text('保存').hitTestable(), findsOneWidget);
    expect(body.hitTestable(), findsOneWidget);
    await tester.enterText(body, '新的校园设定');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(store.readDocument('w', '世界书')!.content, '新的校园设定');
    expect(store.listDocuments('w'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
