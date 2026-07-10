import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';

void main() {
  group('MemoryPrompt', () {
    final now = DateTime(2026);
    const summaryMaxLength = 36;
    const summaryEllipsis = '...';

    test('summary 截断长内容（超过 36 字符）', () {
      final prompt = MemoryPrompt(
        id: 'm1',
        name: '测试',
        content: '这是一段超过三十六个字符的长内容用来验证截断逻辑是否正常工作的补充文字再加几个字',
        updatedAt: now,
      );
      expect(prompt.summary.endsWith(summaryEllipsis), isTrue);
      expect(
        prompt.summary.length,
        lessThanOrEqualTo(summaryMaxLength + summaryEllipsis.length),
      );
    });

    test('summary 保留短内容', () {
      const shortContent = '短内容';
      final prompt = MemoryPrompt(
        id: 'm2',
        name: '测试',
        content: shortContent,
        updatedAt: now,
      );
      expect(prompt.summary, shortContent);
    });
  });
}
