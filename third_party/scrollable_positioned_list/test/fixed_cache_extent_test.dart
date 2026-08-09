import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:scrollable_positioned_list/src/viewport.dart';

void main() {
  testWidgets('固定缓存下 viewport 缩小时不重建已挂载列表项', (tester) async {
    final viewportHeight = ValueNotifier<double>(400);
    final positionsListener = ItemPositionsListener.create();
    var buildCount = 0;
    addTearDown(viewportHeight.dispose);

    final list = ScrollablePositionedList.builder(
      itemCount: 100,
      cacheExtent: 200,
      itemPositionsListener: positionsListener,
      itemBuilder: (context, index) {
        buildCount += 1;
        return SizedBox(height: 50, child: Text('item $index'));
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: viewportHeight,
            child: list,
            builder: (context, height, child) {
              return SizedBox(width: 400, height: height, child: child);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final initialBuildCount = buildCount;

    for (final height in <double>[360, 320, 280, 240, 200]) {
      viewportHeight.value = height;
      await tester.pump();
    }
    await tester.pump();

    expect(buildCount, initialBuildCount);
    final visibleIndexes = positionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemLeadingEdge < 1 && position.itemTrailingEdge > 0,
        )
        .map((position) => position.index)
        .toSet();
    expect(visibleIndexes, containsAll(<int>{0, 1, 2, 3}));
    expect(visibleIndexes, isNot(contains(4)));
  });

  testWidgets('远距滚到超长项底部后恢复稳定 anchor 并保持画面位置', (tester) async {
    final itemScrollController = ItemScrollController();
    final positionsListener = ItemPositionsListener.create();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: ScrollablePositionedList.builder(
              itemCount: 50,
              cacheExtent: 200,
              itemScrollController: itemScrollController,
              itemPositionsListener: positionsListener,
              itemBuilder: (context, index) {
                return SizedBox(height: index == 49 ? 1200 : 100);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollFuture = itemScrollController.scrollTo(
      index: 49,
      alignment: -2,
      duration: const Duration(milliseconds: 120),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    await scrollFuture;
    await tester.pump();

    final viewport = tester.renderObject<UnboundedRenderViewport>(
      find.byType(UnboundedViewport),
    );
    expect(viewport.anchor, 0);

    final targetPosition = positionsListener.itemPositions.value.singleWhere(
      (position) => position.index == 49,
    );
    expect(targetPosition.itemLeadingEdge, closeTo(-2, 0.01));
    expect(targetPosition.itemTrailingEdge, closeTo(1, 0.01));
  });
}
