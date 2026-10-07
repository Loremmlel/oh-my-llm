import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/presentation/models/media_grid_layout_spec.dart';
import 'package:oh_my_llm/features/media/presentation/models/media_grid_tile_metrics.dart';

void main() {
  testWidgets('文字放大增加网格行高，缩略图保留比例且零宽度安全', (tester) async {
    final spec = MediaGridLayoutSpec.forDensity(AppLayoutDensity.standard);
    final metrics = <double, MediaGridTileMetrics>{};
    late MediaGridTileMetrics zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final scale in [1.0, 2.0])
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Builder(
                  builder: (context) {
                    metrics[scale] = MediaGridTileMetrics.resolve(
                      context: context,
                      spec: spec,
                      itemWidth: 220,
                    );
                    zero = MediaGridTileMetrics.resolve(
                      context: context,
                      spec: spec,
                      itemWidth: 0,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
          ],
        ),
      ),
    );
    expect(metrics[2]!.mainAxisExtent, greaterThan(metrics[1]!.mainAxisExtent));
    expect(metrics[2]!.thumbnailHeight, metrics[1]!.thumbnailHeight);
    expect(
      metrics[1]!.thumbnailHeight,
      closeTo(metrics[1]!.contentWidth * 3 / 4, 0.001),
    );
    expect(zero.contentWidth, 0);
    expect(zero.thumbnailHeight, 0);
  });
}
