import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/presentation/models/media_grid_layout_spec.dart';
import 'package:oh_my_llm/features/media/presentation/models/media_grid_tile_metrics.dart';

import '../../../../helpers/test_harness.dart';

/// 在指定 [scaler] 下解析同一网格 tile 的 metrics，并通过 [onResolved] 回传
/// BuildContext 与解析结果，供断言与二次解析复用。
class _ScaledMetricsCapture extends StatelessWidget {
  const _ScaledMetricsCapture({
    required this.spec,
    required this.itemWidth,
    required this.scaler,
    required this.onResolved,
  });

  final MediaGridLayoutSpec spec;
  final double itemWidth;
  final TextScaler scaler;

  final void Function(BuildContext context, MediaGridTileMetrics metrics)
  onResolved;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Builder(
        builder: (context) {
          onResolved(
            context,
            MediaGridTileMetrics.resolve(
              context: context,
              spec: spec,
              itemWidth: itemWidth,
            ),
          );
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

void main() {
  final spec = MediaGridLayoutSpec.forDensity(AppLayoutDensity.standard);
  const itemWidth = 220.0;

  testWidgets('统一行高满足 4:3 缩略图与元数据行高公式', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late MediaGridTileMetrics metrics;

    await pumpTestApp(
      tester,
      preferences: preferences,
      child: _ScaledMetricsCapture(
        spec: spec,
        itemWidth: itemWidth,
        scaler: TextScaler.noScaling,
        onResolved: (context, resolved) => metrics = resolved,
      ),
    );

    expect(
      metrics.thumbnailHeight,
      closeTo(metrics.contentWidth / (4 / 3), 0.001),
    );
    expect(
      metrics.mainAxisExtent,
      closeTo(
        spec.tilePadding * 2 +
            metrics.thumbnailHeight +
            MediaGridTileMetrics.thumbnailMetadataGap +
            metrics.titleHeight +
            MediaGridTileMetrics.metadataLineGap +
            metrics.sizeHeight,
        0.001,
      ),
    );
  });

  testWidgets('TextScaler.linear(2) 下 mainAxisExtent 严格大于未缩放值', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late MediaGridTileMetrics metrics;
    late MediaGridTileMetrics scaledMetrics;

    await pumpTestApp(
      tester,
      preferences: preferences,
      child: Column(
        children: [
          _ScaledMetricsCapture(
            spec: spec,
            itemWidth: itemWidth,
            scaler: TextScaler.noScaling,
            onResolved: (context, resolved) => metrics = resolved,
          ),
          _ScaledMetricsCapture(
            spec: spec,
            itemWidth: itemWidth,
            scaler: TextScaler.linear(2),
            onResolved: (context, resolved) => scaledMetrics = resolved,
          ),
        ],
      ),
    );

    expect(scaledMetrics.mainAxisExtent, greaterThan(metrics.mainAxisExtent));
  });

  testWidgets('同一 context/spec/itemWidth 连续解析三次 mainAxisExtent 完全一致', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late BuildContext capturedContext;

    await pumpTestApp(
      tester,
      preferences: preferences,
      child: _ScaledMetricsCapture(
        spec: spec,
        itemWidth: itemWidth,
        scaler: TextScaler.noScaling,
        onResolved: (context, _) => capturedContext = context,
      ),
    );

    final first = MediaGridTileMetrics.resolve(
      context: capturedContext,
      spec: spec,
      itemWidth: itemWidth,
    );
    final second = MediaGridTileMetrics.resolve(
      context: capturedContext,
      spec: spec,
      itemWidth: itemWidth,
    );
    final third = MediaGridTileMetrics.resolve(
      context: capturedContext,
      spec: spec,
      itemWidth: itemWidth,
    );
    expect(first.mainAxisExtent, equals(second.mainAxisExtent));
    expect(third.mainAxisExtent, equals(first.mainAxisExtent));
  });

  testWidgets('itemWidth 为 0 时安全解析为零宽缩略图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late MediaGridTileMetrics zeroMetrics;

    await pumpTestApp(
      tester,
      preferences: preferences,
      child: _ScaledMetricsCapture(
        spec: spec,
        itemWidth: 0,
        scaler: TextScaler.noScaling,
        onResolved: (context, resolved) => zeroMetrics = resolved,
      ),
    );

    expect(zeroMetrics.contentWidth, 0);
    expect(zeroMetrics.thumbnailHeight, 0);
  });

  testWidgets('负宽度与无限宽度触发 assertion', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    late BuildContext capturedContext;

    await pumpTestApp(
      tester,
      preferences: preferences,
      child: _ScaledMetricsCapture(
        spec: spec,
        itemWidth: itemWidth,
        scaler: TextScaler.noScaling,
        onResolved: (context, _) => capturedContext = context,
      ),
    );

    expect(
      () => MediaGridTileMetrics.resolve(
        context: capturedContext,
        spec: spec,
        itemWidth: -1,
      ),
      throwsAssertionError,
    );
    expect(
      () => MediaGridTileMetrics.resolve(
        context: capturedContext,
        spec: spec,
        itemWidth: double.infinity,
      ),
      throwsAssertionError,
    );
  });
}
