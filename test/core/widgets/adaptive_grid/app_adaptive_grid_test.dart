import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/adaptive_grid/app_adaptive_grid.dart';

void main() {
  testWidgets('网格使用父宽度并仅构建可见项', (tester) async {
    double? itemWidth;
    var buildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 411.42857142857144,
              height: 500,
              child: AppAdaptiveGrid(
                itemCount: 1000,
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                padding: const EdgeInsets.all(12),
                mainAxisExtentBuilder: (_, width) => width,
                itemBuilder: (context, index, width) {
                  buildCount++;
                  if (index == 0) itemWidth = width;
                  return Text('项目$index', key: ValueKey(index));
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(itemWidth, closeTo((411.42857142857144 - 24 - 12) / 2, 0.000001));
    expect(buildCount, greaterThan(0));
    expect(buildCount, lessThan(1000));
  });

  testWidgets('调整父宽度后子项状态保持，计数不重置', (tester) async {
    Widget buildGrid(double width) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 500,
            child: AppAdaptiveGrid(
              itemCount: 30,
              maxCrossAxisExtent: 220,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              padding: const EdgeInsets.all(12),
              mainAxisExtentBuilder: (_, itemWidth) => itemWidth,
              itemBuilder: (context, index, itemWidth) {
                if (index == 0) {
                  return const _CountingCounter(key: ValueKey('计数状态'));
                }
                return Text('项目$index', key: ValueKey(index));
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildGrid(411.42857142857144));

    await tester.tap(find.text('计数1'));
    await tester.pump();
    expect(find.text('计数2'), findsOneWidget);

    // 改变父宽度（列数由 2 变为 3），重新 pump
    await tester.pumpWidget(buildGrid(700));
    await tester.pump();

    expect(find.text('计数2'), findsOneWidget);
  });
}

class _CountingCounter extends StatefulWidget {
  const _CountingCounter({super.key});

  @override
  State<_CountingCounter> createState() => _CountingCounterState();
}

class _CountingCounterState extends State<_CountingCounter> {
  int _count = 1;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('计数$_count'),
    );
  }
}
