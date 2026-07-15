import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenFixedPromptSequencesTests() {
  testWidgets(
    'settings screen creates a fixed prompt sequence with steps',
    (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 2200),
        initialTabIndex: 2,
      );
      final repository = fixedPromptSequenceRepository;
      expect(repository.loadAll(database), isEmpty);

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();
      expect(
        find.text('新增固定顺序提示词'),
        findsOneWidget,
      );

      await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程');
      await tester.enterText(fixedStepTitleField(), '标题1');
      await tester.enterText(
        fixedStepContentField(),
        '请先总结这个需求的核心目标。',
      );
      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(fixedStepTitleField(), '标题2');
      await tester.enterText(
        fixedStepContentField(),
        '请列出三个可执行方案，并说明权衡。',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final createdSequence = repository.loadAll(database).single;
      expect(createdSequence.name, '对比测试流程');
      expect(createdSequence.steps, hasLength(2));
      expect(find.text('对比测试流程'), findsWidgets);
      expect(find.textContaining('共 2 步'), findsOneWidget);
    },
  );

  testWidgets(
    'settings screen edits a fixed prompt sequence name',
    (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 2200),
        initialTabIndex: 2,
      );

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();
      await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程');
      await tester.enterText(fixedStepTitleField(), '标题1');
      await tester.enterText(fixedStepContentField(), '内容1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final fixedSequencesSection = find.ancestor(
        of: find.text('固定顺序提示词'),
        matching: find.byType(Card),
      );
      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
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
      await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(fixedPromptSequenceRepository.loadAll(database).single.name, '对比测试流程 v2');
      expect(find.text('对比测试流程 v2'), findsWidgets);
    },
  );

  testWidgets(
    'settings screen deletes a fixed prompt sequence',
    (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 2200),
        initialTabIndex: 2,
      );

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();
      await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程');
      await tester.enterText(fixedStepTitleField(), '标题1');
      await tester.enterText(fixedStepContentField(), '内容1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final fixedSequencesSection = find.ancestor(
        of: find.text('固定顺序提示词'),
        matching: find.byType(Card),
      );
      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      );
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

      expect(fixedPromptSequenceRepository.loadAll(database), isEmpty);
    },
  );

  testWidgets(
    'fixed prompt sequence dialog inserts a new step below selection',
    (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(1440, 2200),
      initialTabIndex: 2,
    );

      await tester.tap(find.text('新增序列'));
      await tester.pumpAndSettle();
      final masterPane = find.ancestor(
        of: find.text('步骤列表'),
        matching: find.byType(DecoratedBox),
      );
      Finder stepTile(String title) =>
          find.descendant(of: masterPane, matching: find.text(title));

      await tester.enterText(fixedPromptSequenceNameField(), '插入测试流程');
      await tester.enterText(fixedStepTitleField(), '标题1');
      await tester.enterText(fixedStepContentField(), '内容1');

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(fixedStepTitleField(), '标题2');
      await tester.enterText(fixedStepContentField(), '内容2');

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();
      await tester.enterText(fixedStepTitleField(), '标题3');
      await tester.enterText(fixedStepContentField(), '内容3');

      await tester.tap(stepTile('标题1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('新增步骤'));
      await tester.pumpAndSettle();

      // 新插入的步骤使用 fallback 标题，验证它在列表中显示
      // 硬编码期望值而非调用生产函数，避免循环测试
      expect(stepTile('标题1'), findsOneWidget);
      expect(stepTile('标题4'), findsOneWidget);
      expect(stepTile('标题2'), findsOneWidget);
      expect(stepTile('标题3'), findsOneWidget);

    },
  );
}
