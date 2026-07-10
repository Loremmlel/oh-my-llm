import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_role.dart';

void main() {
  group('PromptMessageRole', () {
    test('fromApiValue 已知值正确解析', () {
      expect(PromptMessageRole.fromApiValue('system'), PromptMessageRole.system);
      expect(PromptMessageRole.fromApiValue('user'), PromptMessageRole.user);
      expect(PromptMessageRole.fromApiValue('assistant'), PromptMessageRole.assistant);
    });

    test('fromApiValue 未知值回退到 user', () {
      expect(PromptMessageRole.fromApiValue('unknown'), PromptMessageRole.user);
    });

    test('label 返回正确的展示文本', () {
      expect(PromptMessageRole.system.label, 'System');
      expect(PromptMessageRole.user.label, 'User');
      expect(PromptMessageRole.assistant.label, 'Assistant');
    });
  });
}
