import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

void main() {
  group('PresetPrompt', () {
    final now = DateTime(2026);
    final beforeMsg = PromptMessage(
      id: '1',
      role: PromptMessageRole.user,
      content: '前置消息',
      placement: PromptMessagePlacement.before,
    );
    final afterMsg = PromptMessage(
      id: '2',
      role: PromptMessageRole.user,
      content: '后置消息',
      placement: PromptMessagePlacement.after,
    );

    test('messagesForPlacement 过滤前置消息', () {
      final preset = PresetPrompt(
        id: 'p1',
        name: '测试',
        messages: [beforeMsg, afterMsg],
        updatedAt: now,
      );
      final result = preset
          .messagesForPlacement(PromptMessagePlacement.before)
          .toList();
      expect(result, [beforeMsg]);
    });

    test('messagesForPlacement 过滤后置消息', () {
      final preset = PresetPrompt(
        id: 'p1',
        name: '测试',
        messages: [beforeMsg, afterMsg],
        updatedAt: now,
      );
      final result = preset
          .messagesForPlacement(PromptMessagePlacement.after)
          .toList();
      expect(result, [afterMsg]);
    });

    test('messagesForPlacement 过滤最新输入前消息', () {
      final beforeLatestInputMsg = PromptMessage(
        id: '3',
        role: PromptMessageRole.user,
        content: '最新输入前消息',
        placement: PromptMessagePlacement.beforeLatestInput,
      );
      final preset = PresetPrompt(
        id: 'p1',
        name: '测试',
        messages: [beforeMsg, beforeLatestInputMsg, afterMsg],
        updatedAt: now,
      );
      final result = preset
          .messagesForPlacement(PromptMessagePlacement.beforeLatestInput)
          .toList();
      expect(result, [beforeLatestInputMsg]);
    });

    test('messagesForPlacement 空列表返回空', () {
      final preset = PresetPrompt(
        id: 'p1',
        name: '测试',
        messages: [],
        updatedAt: now,
      );
      expect(
        preset.messagesForPlacement(PromptMessagePlacement.before).toList(),
        isEmpty,
      );
    });
  });
}
