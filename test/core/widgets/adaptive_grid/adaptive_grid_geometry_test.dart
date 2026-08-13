import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/adaptive_grid/adaptive_grid_geometry.dart';

void main() {
  test('列数在 0.5px 容差内保持稳定，越过容差后增加', () {
    AdaptiveGridGeometry resolve(double width) => AdaptiveGridGeometry.resolve(
      availableWidth: width,
      horizontalPadding: 16,
      maxCrossAxisExtent: 160,
      crossAxisSpacing: 8,
    );

    expect(resolve(176).crossAxisCount, 1); // usable = 160
    expect(resolve(176.5).crossAxisCount, 1);
    expect(resolve(176.500001).crossAxisCount, 2);
    expect(resolve(344.5).crossAxisCount, 2);
    expect(resolve(344.500001).crossAxisCount, 3);
  });

  test('长小数宽度重复计算返回相同几何', () {
    final values = List.generate(
      20,
      (_) => AdaptiveGridGeometry.resolve(
        availableWidth: 411.42857142857144,
        horizontalPadding: 24,
        maxCrossAxisExtent: 220,
        crossAxisSpacing: 12,
      ),
    );
    expect(values.map((value) => value.crossAxisCount).toSet(), {2});
    expect(values.map((value) => value.itemCrossAxisExtent).toSet().length, 1);
  });

  test('宽度增长时列数不减少且项目宽度不超过上限加容差', () {
    var previousColumns = 1;
    for (double width = 0; width <= 1600; width += 0.25) {
      final geometry = AdaptiveGridGeometry.resolve(
        availableWidth: width,
        horizontalPadding: 16,
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 8,
      );
      expect(geometry.crossAxisCount, greaterThanOrEqualTo(previousColumns));
      expect(geometry.itemCrossAxisExtent, lessThanOrEqualTo(160.5));
      previousColumns = geometry.crossAxisCount;
    }
  });

  test('零宽安全退化为一列，无效规格触发断言', () {
    final zero = AdaptiveGridGeometry.resolve(
      availableWidth: 0,
      horizontalPadding: 16,
      maxCrossAxisExtent: 160,
      crossAxisSpacing: 8,
    );
    expect(zero.crossAxisCount, 1);
    expect(zero.itemCrossAxisExtent, 0);
    expect(
      () => AdaptiveGridGeometry.resolve(
        availableWidth: double.infinity,
        horizontalPadding: 0,
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 8,
      ),
      throwsAssertionError,
    );
  });
}
