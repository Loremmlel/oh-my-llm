import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

void main() {
  group('Favorite', () {
    test('hasReasoning 只在推理内容非空时为 true', () {
      for (final (:content, :expected) in [
        (content: '', expected: false),
        (content: '思考过程', expected: true),
      ]) {
        final favorite = Favorite(
          id: 'f1',
          userMessageContent: 'q',
          assistantContent: 'a',
          assistantReasoningContent: content,
          createdAt: DateTime(2026),
        );
        expect(favorite.hasReasoning, expected, reason: 'content=$content');
      }
    });

    test('displayTitle 优先使用自定义标题，否则回退用户消息', () {
      for (final (:title, :expected) in [
        (title: '我的标题', expected: '我的标题'),
        (title: null, expected: '用户消息'),
      ]) {
        final favorite = Favorite(
          id: 'f1',
          userMessageContent: '用户消息',
          assistantContent: '回复',
          title: title,
          createdAt: DateTime(2026),
        );
        expect(favorite.displayTitle, expected, reason: 'title=$title');
      }
    });
  });
}
