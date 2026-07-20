import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_placement.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_role.dart';

void main() {
  group('buildPresetPromptMessageFallbackTitle', () {
    test('before 位置生成正确标题', () {
      expect(
        buildPresetPromptMessageFallbackTitle(
          role: PromptMessageRole.user,
          placement: PromptMessagePlacement.before,
          sequence: 1,
        ),
        '前置user1',
      );
    });

    test('beforeLatestInput 位置生成正确标题', () {
      expect(
        buildPresetPromptMessageFallbackTitle(
          role: PromptMessageRole.system,
          placement: PromptMessagePlacement.beforeLatestInput,
          sequence: 2,
        ),
        '最新输入前system2',
      );
    });

    test('after 位置生成正确标题', () {
      expect(
        buildPresetPromptMessageFallbackTitle(
          role: PromptMessageRole.assistant,
          placement: PromptMessagePlacement.after,
          sequence: 3,
        ),
        '后置assistant3',
      );
    });
  });
}
