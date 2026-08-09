import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  group('ChatMessage 可选持久化字段', () {
    test('toJson → fromJson 保留模板元数据与 finishReason', () {
      final original = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
        templatePromptId: 'tpl-1',
        templateVariableValues: const {'lang': 'Dart'},
        finishReason: 'length',
      );

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored.templatePromptId, 'tpl-1');
      expect(restored.templateVariableValues, {'lang': 'Dart'});
      expect(restored.finishReason, 'length');
    });

    test('fromJson 缺失可选字段时回退兼容默认值', () {
      final json = {
        'id': 'test',
        'role': 'user',
        'content': 'hello',
        'createdAt': '2026-01-01T00:00:00.000',
        'userMessageSegments': [],
      };
      final message = ChatMessage.fromJson(json);

      expect(message.templatePromptId, isNull);
      expect(message.templateVariableValues, isEmpty);
      expect(message.finishReason, isNull);
    });
  });
}
