import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_generation_usage.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  group('ChatMessage 可选持久化字段', () {
    test('toJson → fromJson 保留模板元数据、finishReason 与 Token 用量', () {
      final original = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
        templatePromptId: 'tpl-1',
        templateVariableValues: const {'lang': 'Dart'},
        finishReason: 'length',
        tokenUsage: const ChatGenerationUsage(
          inputTokens: 4000,
          outputTokens: 900,
          reasoningTokens: 200,
          cachedInputTokens: 1500,
          cacheWriteInputTokens: 800,
        ),
      );

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored.templatePromptId, 'tpl-1');
      expect(restored.templateVariableValues, {'lang': 'Dart'});
      expect(restored.finishReason, 'length');
      expect(restored.tokenUsage, original.tokenUsage);
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
      expect(message.tokenUsage, isNull);
    });

    test('fromJson 把负数、非整数与全空用量视为未知', () {
      final base = {
        'id': 'test',
        'role': 'assistant',
        'content': 'hello',
        'createdAt': '2026-01-01T00:00:00.000',
      };

      final partiallyValid = ChatMessage.fromJson({
        ...base,
        'tokenUsage': {
          'inputTokens': -1,
          'outputTokens': 0,
          'cachedInputTokens': 1.5,
        },
      });
      final entirelyUnknown = ChatMessage.fromJson({
        ...base,
        'tokenUsage': {'inputTokens': -1},
      });

      expect(
        partiallyValid.tokenUsage,
        const ChatGenerationUsage(outputTokens: 0),
      );
      expect(entirelyUnknown.tokenUsage, isNull);
    });
  });
}
