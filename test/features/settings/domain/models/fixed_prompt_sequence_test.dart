import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';

void main() {
  group('FixedPromptSequence', () {
    final now = DateTime(2026);

    test('summary 有步骤时返回包含步骤数的信息', () {
      final sequence = FixedPromptSequence(
        id: 'f1',
        name: '测试',
        steps: [
          const FixedPromptSequenceStep(id: 's1', content: '步骤一'),
          const FixedPromptSequenceStep(id: 's2', content: '步骤二'),
        ],
        updatedAt: now,
      );
      expect(sequence.summary, '共 2 步');
    });
  });
}
