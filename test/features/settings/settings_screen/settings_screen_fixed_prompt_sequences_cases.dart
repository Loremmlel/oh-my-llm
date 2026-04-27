import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenFixedPromptSequencesTests() {
  testWidgets(
    'settings screen supports fixed prompt sequence CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      // 接收数据库实例以便查询 SQLite 断言。
      final database = await pumpSettingsScreen(tester, preferences: preferences);
      final repo = SqliteFixedPromptSequenceRepository(database);

      expect(find.text('还没有固定顺序提示词'), findsOneWidget);

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '对比测试流程');
      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '请先总结这个需求的核心目标。',
      );
      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '请列出三个可执行方案，并说明权衡。',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('对比测试流程'), findsWidgets);
      expect(repo.loadAll().any((s) => s.name == '对比测试流程'), isTrue);
      expect(find.textContaining('共 2 步'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final editButton = find.widgetWithText(OutlinedButton, '编辑').last;
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '对比测试流程 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('对比测试流程 v2'), findsWidgets);
      expect(repo.loadAll().any((s) => s.name == '对比测试流程 v2'), isTrue);

      final deleteButton = find.widgetWithText(OutlinedButton, '删除').last;
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('还没有固定顺序提示词'), findsOneWidget);
      expect(repo.loadAll(), isEmpty);
    },
  );
}
