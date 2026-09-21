import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oh_my_llm/features/settings/application/ports/preset_import_source.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/silly_tavern_import_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('宏预设编辑保存保留跨位置顺序、关闭条目、空标题和正文空白', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final submitted = Completer<PresetPromptFormData>();
    final preset = PresetPrompt(
      id: 'p',
      name: '变量预设',
      updatedAt: DateTime(2026),
      syntax: PresetPromptSyntax.sillyTavernSubsetV1,
      messages: [
        const PromptMessage(
          id: 'set',
          role: PromptMessageRole.system,
          content: '\n{{setvar::x::约束}}\n',
          placement: PromptMessagePlacement.after,
          enabled: false,
          sourceIdentifier: 'source',
          importInsertionOrder: 1,
        ),
        const PromptMessage(
          id: 'get',
          role: PromptMessageRole.system,
          title: '汇总',
          content: '{{getvar::x}}',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      preferences: await SharedPreferences.getInstance(),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PresetPromptFormDialog(
                initialValue: preset,
                onSubmit: (value) async {
                  submitted.complete(value);
                },
              ),
            ),
            child: const Text('编辑'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('保存'));
    final value = await submitted.future;
    expect(value.syntax, preset.syntax);
    expect(value.messages, preset.messages);
    await settleOverlayTransition(tester);
  });

  testWidgets('选择预设文件后明确显示导入内容并保存有限宏语法', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpTestApp(
      tester,
      preferences: prefs,
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ProviderScope(
                overrides: [
                  presetImportSourceProvider.overrideWithValue(
                    () async => (
                      name: '写作.json',
                      text: '{"prompts":[{"identifier":"one","name":"选一","content":"{{user}}"},{"identifier":"chatHistory","marker":true,"content":""}],"prompt_order":[{"character_id":100001,"order":[{"identifier":"one","enabled":true},{"identifier":"chatHistory","enabled":true}]}]}',
                    ),
                  ),
                ],
                child: const SillyTavernImportDialog(),
              ),
            ),
            child: const Text('打开导入'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('选择 JSON 文件'));
    await tester.pump();
    await tester.pump();
    expect(find.text('导入 1 条，其中 0 条为默认关闭的备用条目。'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('打开导入')),
    );
    await tester.tap(find.text('导入'));
    await settleOverlayTransition(tester);
    final imported = container.read(presetPromptsProvider).single;
    expect(imported.syntax, PresetPromptSyntax.sillyTavernSubsetV1);
    expect(imported.messages.single.content, '{{user}}');
    expect(imported.messages.single.title, '选一');
  });
}
