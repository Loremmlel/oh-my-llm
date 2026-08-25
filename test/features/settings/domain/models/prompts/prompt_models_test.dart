import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

void main() {
  test('FixedPromptSequence summary reports its step count', () {
    final sequence = FixedPromptSequence(
      id: 'f1',
      name: '测试',
      steps: const [
        FixedPromptSequenceStep(id: 's1', content: '步骤一'),
        FixedPromptSequenceStep(id: 's2', content: '步骤二'),
      ],
      updatedAt: DateTime(2026),
    );

    expect(sequence.summary, '共 2 步');
  });

  group('MemoryPrompt summary', () {
    test('keeps short content unchanged', () {
      final prompt = MemoryPrompt(
        id: 'm1',
        name: '测试',
        content: '短内容',
        updatedAt: DateTime(2026),
      );
      expect(prompt.summary, '短内容');
    });

    test('truncates content longer than 36 characters', () {
      final prompt = MemoryPrompt(
        id: 'm2',
        name: '测试',
        content: '这是一段超过三十六个字符的长内容用来验证截断逻辑是否正常工作的补充文字再加几个字',
        updatedAt: DateTime(2026),
      );

      expect(prompt.summary, endsWith('...'));
      expect(prompt.summary.length, lessThanOrEqualTo(39));
    });
  });

  test('PresetPrompt filters messages by every placement', () {
    final messages = [
      const PromptMessage(
        id: 'before',
        role: PromptMessageRole.user,
        content: '前置',
      ),
      const PromptMessage(
        id: 'latest',
        role: PromptMessageRole.system,
        content: '输入前',
        placement: PromptMessagePlacement.beforeLatestInput,
      ),
      const PromptMessage(
        id: 'after',
        role: PromptMessageRole.assistant,
        content: '后置',
        placement: PromptMessagePlacement.after,
      ),
    ];
    final prompt = PresetPrompt(
      id: 'p1',
      name: '测试',
      messages: messages,
      updatedAt: DateTime(2026),
    );
    const cases = [
      (placement: PromptMessagePlacement.before, expectedId: 'before'),
      (
        placement: PromptMessagePlacement.beforeLatestInput,
        expectedId: 'latest',
      ),
      (placement: PromptMessagePlacement.after, expectedId: 'after'),
    ];

    for (final testCase in cases) {
      expect(prompt.messagesForPlacement(testCase.placement).map((m) => m.id), [
        testCase.expectedId,
      ], reason: testCase.placement.name);
    }
  });

  test('PromptMessageRole parses API values, labels them, and falls back', () {
    const cases = [
      (apiValue: 'system', role: PromptMessageRole.system, label: 'System'),
      (apiValue: 'user', role: PromptMessageRole.user, label: 'User'),
      (
        apiValue: 'assistant',
        role: PromptMessageRole.assistant,
        label: 'Assistant',
      ),
    ];

    for (final testCase in cases) {
      expect(PromptMessageRole.fromApiValue(testCase.apiValue), testCase.role);
      expect(testCase.role.label, testCase.label);
    }
    expect(PromptMessageRole.fromApiValue('unknown'), PromptMessageRole.user);
  });

  test(
    'PromptMessagePlacement parses API values, labels them, and falls back',
    () {
      const cases = [
        (
          apiValue: 'before',
          placement: PromptMessagePlacement.before,
          label: '前置',
        ),
        (
          apiValue: 'beforeLatestInput',
          placement: PromptMessagePlacement.beforeLatestInput,
          label: '最新输入前',
        ),
        (
          apiValue: 'after',
          placement: PromptMessagePlacement.after,
          label: '后置',
        ),
      ];

      for (final testCase in cases) {
        expect(
          PromptMessagePlacement.fromApiValue(testCase.apiValue),
          testCase.placement,
        );
        expect(testCase.placement.label, testCase.label);
      }
      expect(
        PromptMessagePlacement.fromApiValue('unknown'),
        PromptMessagePlacement.before,
      );
    },
  );

  test('fallback titles combine placement, role, and sequence', () {
    const cases = [
      (
        role: PromptMessageRole.user,
        placement: PromptMessagePlacement.before,
        sequence: 1,
        expected: '前置user1',
      ),
      (
        role: PromptMessageRole.system,
        placement: PromptMessagePlacement.beforeLatestInput,
        sequence: 2,
        expected: '最新输入前system2',
      ),
      (
        role: PromptMessageRole.assistant,
        placement: PromptMessagePlacement.after,
        sequence: 3,
        expected: '后置assistant3',
      ),
    ];

    for (final testCase in cases) {
      expect(
        buildPresetPromptMessageFallbackTitle(
          role: testCase.role,
          placement: testCase.placement,
          sequence: testCase.sequence,
        ),
        testCase.expected,
      );
    }
  });

  test('PromptMessage round-trip preserves beforeLatestInput placement', () {
    const original = PromptMessage(
      id: 'rt-1',
      role: PromptMessageRole.user,
      title: '测试标题',
      content: '测试内容',
      placement: PromptMessagePlacement.beforeLatestInput,
      enabled: false,
    );

    expect(PromptMessage.fromJson(original.toJson()), original);
  });
}
