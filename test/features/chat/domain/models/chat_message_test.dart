import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  group('ChatMessage 模板元数据字段', () {
    test('默认 templatePromptId 为 null', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      expect(message.templatePromptId, isNull);
    });

    test('默认 templateVariableValues 为空 map', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      expect(message.templateVariableValues, isEmpty);
    });

    test('fromJson 反序列化 templatePromptId 和 templateVariableValues', () {
      final json = {
        'id': 'test',
        'role': 'user',
        'content': 'hello',
        'createdAt': '2026-01-01T00:00:00.000',
        'parentId': null,
        'reasoningContent': '',
        'assistantModelDisplayName': '',
        'appliedCheckpointTitle': '',
        'userMessageSegments': [],
        'templatePromptId': 'tpl-1',
        'templateVariableValues': {'key': 'value'},
      };
      final message = ChatMessage.fromJson(json);
      expect(message.templatePromptId, 'tpl-1');
      expect(message.templateVariableValues, {'key': 'value'});
    });

    test('fromJson 缺失新字段时回退默认值', () {
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
    });

    test('toJson 包含新字段', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
        templatePromptId: 'tpl-1',
        templateVariableValues: {'lang': 'Dart'},
      );
      final json = message.toJson();
      expect(json['templatePromptId'], 'tpl-1');
      expect(json['templateVariableValues'], {'lang': 'Dart'});
    });

    test('copyWith 支持新字段', () {
      final original = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      final copied = original.copyWith(
        templatePromptId: 'tpl-2',
        templateVariableValues: {'x': 'y'},
      );
      expect(copied.templatePromptId, 'tpl-2');
      expect(copied.templateVariableValues, {'x': 'y'});
      expect(copied.id, 'test');
      expect(copied.content, 'hello');
    });
  });
}
