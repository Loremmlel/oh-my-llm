import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_placement.dart';

void main() {
  group('PromptMessagePlacement', () {
    test('fromApiValue 已知值正确解析', () {
      expect(PromptMessagePlacement.fromApiValue('before'), PromptMessagePlacement.before);
      expect(PromptMessagePlacement.fromApiValue('beforeLatestInput'), PromptMessagePlacement.beforeLatestInput);
      expect(PromptMessagePlacement.fromApiValue('after'), PromptMessagePlacement.after);
    });

    test('fromApiValue 未知值回退到 before', () {
      expect(PromptMessagePlacement.fromApiValue('unknown'), PromptMessagePlacement.before);
    });

    test('label 返回正确的展示文本', () {
      expect(PromptMessagePlacement.before.label, '前置');
      expect(PromptMessagePlacement.beforeLatestInput.label, '最新输入前');
      expect(PromptMessagePlacement.after.label, '后置');
    });
  });
}
