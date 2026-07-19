import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

void main() {
  group('Favorite', () {
    test('hasReasoning 为 true 当 reasoningContent 非空', () {
      final fav = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        assistantReasoningContent: '思考过程',
        createdAt: DateTime(2026),
      );
      expect(fav.hasReasoning, isTrue);
    });

    test('hasReasoning 为 false 当 reasoningContent 为空', () {
      final fav = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026),
      );
      expect(fav.hasReasoning, isFalse);
    });

    test('copyWith 覆盖指定字段', () {
      final original = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026),
      );
      final copied = original.copyWith(assistantContent: 'b');
      expect(copied.id, 'f1');
      expect(copied.assistantContent, 'b');
      expect(copied.userMessageContent, 'q');
    });

    test('copyWith + clearCollectionId 将 collectionId 置为 null', () {
      final original = Favorite(
        id: 'f1',
        collectionId: 'col-1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026),
      );
      final cleared = original.copyWith(clearCollectionId: true);
      expect(cleared.collectionId, isNull);
    });

    test('copyWith 不传 clearCollectionId 时保留原有 collectionId', () {
      final original = Favorite(
        id: 'f1',
        collectionId: 'col-1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026),
      );
      final copied = original.copyWith(assistantContent: 'b');
      expect(copied.collectionId, 'col-1');
    });

    test('Equatable 相等性', () {
      final a = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Equatable 不等性', () {
      final a = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = Favorite(
        id: 'f2',
        userMessageContent: 'q',
        assistantContent: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(a, isNot(equals(b)));
    });

    test('displayTitle 使用自定义标题', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '这是一段很长的用户消息内容',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
        title: '我的自定义标题',
      );

      expect(favorite.displayTitle, '我的自定义标题');
    });

    test('displayTitle 在无自定义标题时 fallback 到 userMessageContent', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '用户消息原文',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
      );

      expect(favorite.displayTitle, '用户消息原文');
    });

    test('copyWith 更新 title', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '消息',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
      );

      final updated = favorite.copyWith(title: '新标题');
      expect(updated.title, '新标题');
      expect(updated.userMessageContent, '消息');
    });

    test('copyWith + clearTitle 将 title 置为 null', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '消息',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
        title: '旧标题',
      );

      final cleared = favorite.copyWith(clearTitle: true);
      expect(cleared.title, isNull);
    });

    test('copyWith 保留 sourceAssistantMessageId', () {
      final fav = Favorite(
        id: 'f1',
        userMessageContent: 'q',
        assistantContent: 'a',
        sourceAssistantMessageId: 'msg-42',
        createdAt: DateTime(2026),
      );
      expect(fav.sourceAssistantMessageId, 'msg-42');
      expect(fav.copyWith().sourceAssistantMessageId, 'msg-42');
      expect(fav.copyWith(sourceAssistantMessageId: 'msg-99').sourceAssistantMessageId, 'msg-99');
    });
  });
}
