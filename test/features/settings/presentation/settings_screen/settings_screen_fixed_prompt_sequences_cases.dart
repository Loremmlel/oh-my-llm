import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/prompts/sqlite_fixed_prompt_sequence_repository.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

void registerSettingsScreenFixedPromptSequencesTests() {
  testWidgets('创建固定提示词序列，在选中步骤后插入并持久保存顺序', (tester) async {
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
    expect(savedSteps.map((step) => step.content), [
      '内容1',
      '内容1.5',
      '内容2',
      '内容3',
    ]);
    expect(
      fixedPromptSequenceRepository.loadAll(database).single.name,
      '插入测试流程',
    );
    expect(find.text('插入测试流程'), findsWidgets);
    expect(find.textContaining('共 4 步'), findsOneWidget);
  });
}
