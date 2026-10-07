import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/fixed_prompt_sequence_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/memory_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart';

import '../../../../../../helpers/fixtures.dart';
import '../../../../../../helpers/test_harness.dart';
import '../../../../../../helpers/async/widget_test_animation.dart';

void main() {
  const original = '第一段\r\n\r\n第二段\r第三段';
  const normalized = '第一段\n\n第二段\n第三段';
  final forms = <String, Widget Function(Future<void> Function(String))>{
    '固定顺序提示词': (save) => FixedPromptSequenceFormDialog(
      initialValue: TestFixtures.fixedSequence(
        id: 'sequence',
        steps: [
          TestFixtures.sequenceStep(id: 'step', title: '步骤', content: original),
        ],
      ),
      onSubmit: (data) => save(data.steps.single.content),
    ),
    '预设提示词': (save) => PresetPromptFormDialog(
      initialValue: TestFixtures.presetPrompt(
        id: 'preset',
        messages: [
          TestFixtures.promptMessage(
            id: 'message',
            title: '条目',
            content: original,
          ),
        ],
      ),
      onSubmit: (data) => save(data.messages.single.content),
    ),
    '模板提示词': (save) => TemplatePromptFormDialog(
      initialValue: TestFixtures.templatePrompt(
        id: 'template',
        content: original,
        variables: const [],
      ),
      onSubmit: (data) => save(data.content),
    ),
    '记忆提示词': (save) => MemoryPromptFormDialog(
      initialValue: TestFixtures.memoryPrompt(id: 'memory', content: original),
      onSubmit: (data) => save(data.content),
    ),
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in forms.entries) {
    for (final action in ['未修改保存', '粘贴后保存', '取消']) {
      testWidgets('${entry.key}$action使用LF编辑并遵守原文保存约定', (tester) async {
        String? saved;
        await pumpTestApp(
          tester,
          preferences: await SharedPreferences.getInstance(),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => entry.value((text) async => saved = text),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await settleOverlayTransition(tester);
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller is LongTextEditingController,
        );
        expect(field, findsOneWidget);
        final controller = tester.widget<TextField>(field).controller!;
        expect(controller.text, normalized);
        if (action == '粘贴后保存') {
          await tester.enterText(field, '$normalized\r\n新增');
          await tester.pump();
          expect(controller.text, '$normalized\n新增');
        } else {
          await tester.tap(field);
          await tester.pump();
        }
        await tester.tap(find.text(action == '取消' ? '取消' : '保存'));
        await settleOverlayTransition(tester);
        expect(saved, switch (action) {
          '未修改保存' => original,
          '粘贴后保存' => '$normalized\n新增',
          _ => null,
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
