import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_document_editor.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('窄屏创建剧本格式错误保留输入，可修正保存并在键盘弹出时改名查看备忘', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final store = SqliteAgentStore(db);
    store.saveWorkspace(AgentWorkspace(id: 'novel', title: '校园'));
    final preferences = await TestFixtures.seedPreferences(database: db);
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: db,
      viewportSize: const Size(390, 844),
      child: const AgentScreen(),
    );
    showAgentDocumentEditor(tester.element(find.byType(AgentScreen)));
    await settleOverlayTransition(tester);
    await tester.tap(find.byType(DropdownButtonFormField<AgentDocumentKind>));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('剧本').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('查看示例'));
    await settleOverlayTransition(tester);
    expect(find.text(agentScriptExample), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    final body = find.widgetWithText(TextField, '正文');
    await tester.enterText(body, '保留这份未写完的剧本');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('请在剧本开头').hitTestable(), findsOneWidget);
    expect(find.text('保留这份未写完的剧本'), findsOneWidget);
    await tester.enterText(body, agentScriptExample);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    final saved = store.readDocument('novel', '秋季校园风波')!;
    expect(saved.content, agentScriptExample);
    showAgentDocumentEditor(
      tester.element(find.byType(AgentScreen)),
      document: saved,
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('剧本备忘'));
    await settleOverlayTransition(tester);
    expect(find.textContaining('当前内容尚无备忘'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await settleOverlayTransition(tester);
    expect(find.text('保存').hitTestable(), findsOneWidget);
    expect(body.hitTestable(), findsOneWidget);
    await tester.enterText(
      body,
      agentScriptExample.replaceFirst('name: 秋季校园风波', 'name: 校园来信'),
    );
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(store.readDocument('novel', '校园来信')!.id, saved.id);
    expect(store.readDocument('novel', '秋季校园风波'), isNull);
    expect(tester.takeException(), isNull);
  });
}
