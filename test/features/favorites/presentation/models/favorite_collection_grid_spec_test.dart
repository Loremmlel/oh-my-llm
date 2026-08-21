import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/presentation/models/favorite_collection_grid_spec.dart';

void main() {
  group('FavoriteCollectionGridSpec 列数推导', () {
    final spec = const FavoriteCollectionGridSpec();

    test('窄视口退化为单列', () {
      expect(spec.crossAxisCountForWidth(320), 1);
    });

    test('中等视口随父约束连续增加列数', () {
      expect(spec.crossAxisCountForWidth(600), 2);
      expect(spec.crossAxisCountForWidth(720), greaterThan(1));
      expect(
        spec.crossAxisCountForWidth(720),
        lessThanOrEqualTo(spec.crossAxisCountForWidth(1200)),
      );
    });

    test('宽视口保持有限列数且卡片不超过限宽太多', () {
      final columns = spec.crossAxisCountForWidth(1200);
      expect(columns, greaterThan(2));
      // 每列实际宽度不超过规格限宽的一个间距量级，避免卡片无限拉伸。
      final usable = 1200 - spec.padding.horizontal;
      final itemWidth = (usable - spec.spacing * (columns - 1)) / columns;
      expect(
        itemWidth,
        lessThanOrEqualTo(spec.maxCrossAxisExtent + spec.spacing),
      );
    });

    test('列数随宽度单调不减', () {
      var previous = spec.crossAxisCountForWidth(200);
      for (var width = 300; width <= 1600; width += 100) {
        final current = spec.crossAxisCountForWidth(width.toDouble());
        expect(current, greaterThanOrEqualTo(previous), reason: 'width=$width');
        previous = current;
      }
    });
  });

  group('FavoriteCollectionGridSpec 卡片几何', () {
    test('卡片主轴高度为固定正值，保证同一行稳定对齐', () {
      final spec = const FavoriteCollectionGridSpec();

      expect(spec.mainAxisExtent, greaterThan(0));
    });

    test('网格内边距左右对称，保证列宽推导一致', () {
      final spec = const FavoriteCollectionGridSpec();

      expect(spec.padding.left, spec.padding.right);
      expect(spec.padding.horizontal, greaterThan(0));
    });
  });
}
