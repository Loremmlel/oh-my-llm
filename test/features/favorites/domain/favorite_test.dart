import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

Favorite _makeFavorite({String? title, String reasoningContent = ''}) {
  return Favorite(
    id: 'f1',
    collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
    collectionAssignedAt: DateTime(2026, 1, 2),
    userMessageContent: '用户消息',
    assistantContent: '回复',
    assistantReasoningContent: reasoningContent,
    title: title,
    createdAt: DateTime(2026),
  );
}

void main() {
  group('Favorite', () {
    test('hasReasoning 只在推理内容非空时为 true', () {
      for (final (:content, :expected) in [
        (content: '', expected: false),
        (content: '思考过程', expected: true),
      ]) {
        final favorite = _makeFavorite(title: null, reasoningContent: content);
        expect(favorite.hasReasoning, expected, reason: 'content=$content');
      }
    });

    test('displayTitle 优先使用自定义标题，否则回退用户消息', () {
      for (final (:title, :expected) in [
        (title: '我的标题', expected: '我的标题'),
        (title: null, expected: '用户消息'),
      ]) {
        final favorite = _makeFavorite(title: title);
        expect(favorite.displayTitle, expected, reason: 'title=$title');
      }
    });

    test('copyWith 保持归属字段非空且可更新归属时间', () {
      final favorite = _makeFavorite(title: null);

      // copyWith 不提供清除归属的入口：归属必属一个收藏夹。
      final copied = favorite.copyWith(
        collectionAssignedAt: DateTime(2026, 5, 1),
      );
      expect(
        copied.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(copied.collectionAssignedAt, DateTime(2026, 5, 1));
      expect(favorite.collectionAssignedAt, DateTime(2026, 1, 2));

      final moved = favorite.copyWith(
        collectionId: 'col-target',
        collectionAssignedAt: DateTime(2026, 6, 1),
      );
      expect(moved.collectionId, 'col-target');
      expect(moved.collectionAssignedAt, DateTime(2026, 6, 1));
    });
  });
}
