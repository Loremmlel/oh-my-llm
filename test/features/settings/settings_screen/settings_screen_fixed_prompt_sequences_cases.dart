import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenFixedPromptSequencesTests() {
  testWidgets(
    'settings screen supports fixed prompt sequence CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      // 接收数据库实例以便查询 SQLite 断言。
      final database = await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
      );
      final repo = SqliteFixedPromptSequenceRepository(database);

      expect(find.text('还没有固定顺序提示词'), findsOneWidget);

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fixed-prompt-sequence-form-layout')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(0), '对比测试流程');
      await tester.enterText(find.byType(TextFormField).at(1), '标题1');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '请先总结这个需求的核心目标。',
      );
      expect(find.text('步骤 1 · 标题1'), findsOneWidget);
      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '标题2');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '请列出三个可执行方案，并说明权衡。',
      );
      expect(find.text('步骤 2 · 标题2'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('对比测试流程'), findsWidgets);
      expect(repo.loadAll().any((s) => s.name == '对比测试流程'), isTrue);
      expect(find.textContaining('共 2 步'), findsOneWidget);

      final sequenceTitle = find.text('对比测试流程').last;
      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      );
      final fixedSequencesSection = find.ancestor(
        of: find.text('固定顺序提示词'),
        matching: find.byType(Card),
      );
      await tester.dragUntilVisible(
        sequenceTitle,
        settingsList.first,
        const Offset(0, -300),
      );
      final editButton = find.descendant(
        of: fixedSequencesSection.first,
        matching: find.widgetWithText(OutlinedButton, '编辑'),
      );
      await tester.dragUntilVisible(
        editButton,
        settingsList.first,
        const Offset(0, -300),
      );
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '对比测试流程 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('对比测试流程 v2'), findsWidgets);
      expect(repo.loadAll().any((s) => s.name == '对比测试流程 v2'), isTrue);

      final deleteButton = find.descendant(
        of: fixedSequencesSection.first,
        matching: find.widgetWithText(OutlinedButton, '删除'),
      );
      await tester.dragUntilVisible(
        deleteButton,
        settingsList.first,
        const Offset(0, -300),
      );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('还没有固定顺序提示词'), findsOneWidget);
      expect(repo.loadAll(), isEmpty);
    },
  );

  testWidgets('fixed prompt sequence dialog keeps wide master header visible', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      size: const Size(1440, 2200),
    );

    await tester.tap(find.text('新增序列'));
    await tester.pumpAndSettle();

    final masterPane = find.byKey(
      const ValueKey('fixed-prompt-sequence-master-pane'),
    );
    final addStepButton = find.descendant(
      of: masterPane,
      matching: find.widgetWithText(OutlinedButton, '新增步骤'),
    );

    for (var index = 2; index <= 20; index++) {
      await tester.tap(addStepButton);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final header = find.descendant(of: masterPane, matching: find.text('步骤列表'));
    final stepList = find.descendant(
      of: masterPane,
      matching: find.byType(ListView),
    );
    final headerOffsetBefore = tester.getTopLeft(header);

    await tester.dragUntilVisible(
      find.text('步骤 20 · 标题20'),
      stepList,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('步骤 20 · 标题20'), findsOneWidget);
    expect(tester.getTopLeft(header).dy, headerOffsetBefore.dy);
    expect(addStepButton, findsOneWidget);
  });
}
