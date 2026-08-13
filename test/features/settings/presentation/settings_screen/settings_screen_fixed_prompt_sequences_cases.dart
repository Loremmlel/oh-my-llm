import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/prompts/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';

import '../../../../helpers/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

FixedPromptSequence _seededSequence() => FixedPromptSequence(
  id: 'sequence-seeded',
  name: '对比测试流程',
  steps: const [
    FixedPromptSequenceStep(id: 'step-seeded', title: '标题1', content: '内容1'),
  ],
  updatedAt: DateTime(2026),
);

void registerSettingsScreenFixedPromptSequencesTests() {
  testWidgets('settings screen creates a fixed prompt sequence with steps', (
    tester,
  ) async {
    final database = await setUpSettingsScreen(
      tester,
      size: const Size(1440, 2200),
      initialTabIndex: 2,
    );
    final repository = fixedPromptSequenceRepository;
    expect(repository.loadAll(database), isEmpty);

    await tester.tap(find.text('新增序列'));
    await settleOverlayTransition(tester);
    expect(find.text('新增固定顺序提示词'), findsOneWidget);

    await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程');
    await tester.enterText(fixedStepTitleField(), '标题1');
    await tester.enterText(fixedStepContentField(), '请先总结这个需求的核心目标。');
    await tester.tap(find.text('新增步骤'));
    // 步骤插入是 setState 直改列表，无动画
    await tester.pump();
    await tester.enterText(fixedStepTitleField(), '标题2');
    await tester.enterText(fixedStepContentField(), '请列出三个可执行方案，并说明权衡。');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdSequence = repository.loadAll(database).single;
    expect(createdSequence.name, '对比测试流程');
    expect(createdSequence.steps, hasLength(2));
    expect(find.text('对比测试流程'), findsWidgets);
    expect(find.textContaining('共 2 步'), findsOneWidget);
  });

  testWidgets('settings screen edits a fixed prompt sequence name', (
    tester,
  ) async {
    final database = await setUpSettingsScreen(
      tester,
      size: const Size(1440, 2200),
      initialTabIndex: 2,
      fixedPromptSequences: [_seededSequence()],
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '编辑'));
    await settleOverlayTransition(tester);
    await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程 v2');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    expect(
      fixedPromptSequenceRepository.loadAll(database).single.name,
      '对比测试流程 v2',
    );
    expect(find.text('对比测试流程 v2'), findsWidgets);
  });

  testWidgets('settings screen deletes a fixed prompt sequence', (
    tester,
  ) async {
    final database = await setUpSettingsScreen(
      tester,
      size: const Size(1440, 2200),
      initialTabIndex: 2,
      fixedPromptSequences: [_seededSequence()],
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '删除'));
    // 删除直接走 Future 链，状态更新单帧即可
    await tester.pump();

    expect(fixedPromptSequenceRepository.loadAll(database), isEmpty);
  });

  testWidgets(
    'fixed prompt sequence dialog inserts below selection and persists order',
    (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 2200),
        initialTabIndex: 2,
      );

      await tester.tap(find.text('新增序列'));
      await settleOverlayTransition(tester);

      await tester.enterText(fixedPromptSequenceNameField(), '插入测试流程');
      await tester.enterText(fixedStepTitleField(), '标题1');
      await tester.enterText(fixedStepContentField(), '内容1');

      await tester.tap(find.text('新增步骤'));
      // 步骤插入与选中都是 setState，单帧即可
      await tester.pump();
      await tester.enterText(fixedStepTitleField(), '标题2');
      await tester.enterText(fixedStepContentField(), '内容2');

      await tester.tap(find.text('新增步骤'));
      await tester.pump();
      await tester.enterText(fixedStepTitleField(), '标题3');
      await tester.enterText(fixedStepContentField(), '内容3');

      await tester.tap(find.text('标题1'));
      await tester.pump();

      await tester.tap(find.text('新增步骤'));
      await tester.pump();
      await tester.enterText(fixedStepTitleField(), '标题1.5');
      await tester.enterText(fixedStepContentField(), '内容1.5');
      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      final savedSteps = fixedPromptSequenceRepository
          .loadAll(database)
          .single
          .steps;
      expect(savedSteps.map((step) => step.title), [
        '标题1',
        '标题1.5',
        '标题2',
        '标题3',
      ]);
    },
  );
}
