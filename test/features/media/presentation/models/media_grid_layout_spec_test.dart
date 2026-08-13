import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/presentation/models/media_grid_layout_spec.dart';

void main() {
  final cases = [
    (AppLayoutDensity.compact, 160.0, 8.0, 8.0, 1),
    (AppLayoutDensity.standard, 220.0, 12.0, 12.0, 2),
    (AppLayoutDensity.comfortable, 360.0, 16.0, 16.0, 2),
  ];
  for (final testCase in cases) {
    test('${testCase.$1.name} 映射为批准的媒体网格规格', () {
      final spec = MediaGridLayoutSpec.forDensity(testCase.$1);
      expect(spec.maxCrossAxisExtent, testCase.$2);
      expect(spec.spacing, testCase.$3);
      expect(spec.padding, EdgeInsets.all(testCase.$3));
      expect(spec.tilePadding, testCase.$4);
      expect(spec.thumbnailAspectRatio, 4 / 3);
      expect(spec.maxTitleLines, testCase.$5);
    });
  }
}
