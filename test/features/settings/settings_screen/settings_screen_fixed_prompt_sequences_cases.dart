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

  testWidgets(
    'fixed prompt sequence dialog only keeps outer scroll on compact layout',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
      );

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-form-dialog-outer-scroll-view')),
        findsNothing,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
      );

      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      );
      final addSequenceButton = find.widgetWithText(FilledButton, '新增序列');
      await tester.dragUntilVisible(
        addSequenceButton,
        settingsList.first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(addSequenceButton);
      await tester.pumpAndSettle();
      await tester.tap(addSequenceButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-form-dialog-outer-scroll-view')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'fixed prompt sequence dialog inserts a new step below selection',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
      );

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '插入测试流程');
      await tester.enterText(find.byType(TextFormField).at(1), '标题1');
      await tester.enterText(find.byType(TextFormField).at(2), '内容1');

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '标题2');
      await tester.enterText(find.byType(TextFormField).at(2), '内容2');

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '标题3');
      await tester.enterText(find.byType(TextFormField).at(2), '内容3');

      await tester.tap(find.text('步骤 1 · 标题1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();

      expect(find.text('步骤 1 · 标题1'), findsOneWidget);
      expect(find.text('步骤 2 · 标题4'), findsOneWidget);
      expect(find.text('步骤 3 · 标题2'), findsOneWidget);
      expect(find.text('步骤 4 · 标题3'), findsOneWidget);

      final step1Top = tester.getTopLeft(find.text('步骤 1 · 标题1')).dy;
      final insertedTop = tester.getTopLeft(find.text('步骤 2 · 标题4')).dy;
      final step2Top = tester.getTopLeft(find.text('步骤 3 · 标题2')).dy;
      final step3Top = tester.getTopLeft(find.text('步骤 4 · 标题3')).dy;
      expect(step1Top, lessThan(insertedTop));
      expect(insertedTop, lessThan(step2Top));
      expect(step2Top, lessThan(step3Top));

      final titleField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(1),
      );
      final contentField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(2),
      );
      expect(titleField.controller?.text, '标题4');
      expect(contentField.controller?.text, isEmpty);
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

  testWidgets('fixed prompt sequence dialog locks wide detail pane scroll', (
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

    final detailPane = find.byKey(
      const ValueKey('fixed-prompt-sequence-detail-pane'),
    );
    final deleteButton = find.descendant(
      of: detailPane,
      matching: find.widgetWithText(OutlinedButton, '删除当前步骤'),
    );

    expect(
      find.descendant(
        of: detailPane,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );

    final contentField = tester
        .widgetList<TextField>(
          find.descendant(of: detailPane, matching: find.byType(TextField)),
        )
        .last;
    expect(contentField.expands, isTrue);
    expect(contentField.maxLines, isNull);
    expect(contentField.minLines, isNull);

    final detailRect = tester.getRect(detailPane);
    final deleteRect = tester.getRect(deleteButton);
    expect(deleteRect.top, greaterThanOrEqualTo(detailRect.top));
    expect(deleteRect.bottom, lessThanOrEqualTo(detailRect.bottom));
  });
}
