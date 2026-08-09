import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
}
