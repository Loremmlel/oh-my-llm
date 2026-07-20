import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_placement.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_role.dart';

void main() {
  group('PromptMessage', () {
    test('toJson/fromJson round-trip 保留 beforeLatestInput placement', () {
      final original = PromptMessage(
        id: 'rt-1',
        role: PromptMessageRole.user,
        title: '测试标题',
        content: '测试内容',
        placement: PromptMessagePlacement.beforeLatestInput,
        enabled: false,
      );
      final restored = PromptMessage.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.placement, PromptMessagePlacement.beforeLatestInput);
    });
  });
}
