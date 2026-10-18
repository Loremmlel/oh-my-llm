import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/prompts/preset_prompt_panel.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../../../../../helpers/async/widget_test_animation.dart';
import '../../../../../helpers/fixtures.dart';
import '../../../../../helpers/test_harness.dart';

class _FailingPresetsController extends PresetPromptsController {
  final saveResult = Completer<void>();

  @override
  List<PresetPrompt> build() => [
    TestFixtures.presetPrompt(id: 'a', name: '预设甲'),
    TestFixtures.presetPrompt(id: 'b', name: '预设乙'),
  ];

  @override
  Future<void> setRandomHeader(String presetId, bool enabled) =>
      saveResult.future;
}

void main() {
  for (final failBeforeSelection in [true, false]) {
    testWidgets(
      failBeforeSelection ? '预设保存失败后切换选择会清除旧错误' : '切换预设后收到旧保存失败不会污染新选择',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final controller = _FailingPresetsController();
        String? selectedId = 'a';
        await pumpTestApp(
          tester,
          preferences: preferences,
          viewportSize: const Size(390, 844),
          extraOverrides: [
            presetPromptsProvider.overrideWith(() => controller),
            activeChatConversationProvider.overrideWithValue(
              ChatConversation.fromJson(
                TestFixtures.conversation('chat', '测试对话', DateTime(2026)),
              ),
            ),
          ],
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PresetPromptPanel(
                selectedPresetPromptId: selectedId,
                onPresetPromptSelected: (value) =>
                    setState(() => selectedId = value),
              ),
            ),
          ),
        );
        await tester.tap(find.text('头部随机字符'));
        await tester.pump();
        if (failBeforeSelection) {
          controller.saveResult.completeError(StateError('保存失败'));
          await settleAnimatedWidgetTransition(tester);
          expect(find.text('预设设置保存失败，请重试'), findsOneWidget);
        }
        await tester.tap(
          find.widgetWithText(AppDropdownField<String>, '预设 Prompt'),
        );
        await settleOverlayTransition(tester);
        await tester.tap(find.text('预设乙').last);
        await settleOverlayTransition(tester);
        expect(selectedId, 'b');
        if (!failBeforeSelection) {
          controller.saveResult.completeError(StateError('保存失败'));
          await settleAnimatedWidgetTransition(tester);
        }
        expect(find.text('预设设置保存失败，请重试'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
