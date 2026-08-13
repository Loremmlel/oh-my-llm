import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

void main() {
  test('共享布局令牌保持已批准的固定值', () {
    expect(
      [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ],
      [4, 8, 12, 16, 24, 32],
    );
    expect(
      [AppRadii.sm, AppRadii.md, AppRadii.lg, AppRadii.xl],
      [8, 12, 18, 24],
    );
    expect(
      [AppContentWidths.readable, AppContentWidths.form, AppContentWidths.wide],
      [720, 900, 1200],
    );
    expect(
      [
        AppInteractionSizes.minimumHitTarget,
        AppInteractionSizes.compactVisualControl,
        AppInteractionSizes.standardVisualControl,
      ],
      [48, 32, 40],
    );
  });

  test('共享密度只暴露紧凑、标准、舒适三个等级', () {
    expect(AppLayoutDensity.values, [
      AppLayoutDensity.compact,
      AppLayoutDensity.standard,
      AppLayoutDensity.comfortable,
    ]);
  });
}
