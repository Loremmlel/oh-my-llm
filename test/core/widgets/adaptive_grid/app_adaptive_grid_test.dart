import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/adaptive_grid/app_adaptive_grid.dart';

void main() {
  testWidgets('网格使用父宽度而不是整窗宽度', (tester) async {
    double? itemWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 411.42857142857144,
              height: 500,
              child: AppAdaptiveGrid(
                itemCount: 30,
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                padding: const EdgeInsets.all(12),
                mainAxisExtentBuilder: (_, width) => width,
                itemBuilder: (context, index, width) {
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
  });

  testWidgets('惰性构建：1000 个 item 初帧只构建可见项', (tester) async {
    var buildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
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
                  return Text('项目$index', key: ValueKey(index));
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(buildCount, lessThan(1000));
  });

  testWidgets('调整父宽度后子项状态保持，计数不重置', (tester) async {
    var stateCreations = 0;
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
                  return _CountingCounter(
                    key: const ValueKey('计数状态'),
                    initialCount: 1,
                    onStateCreated: () => stateCreations++,
                  );
                }
                return Text('项目$index', key: ValueKey(index));
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildGrid(411.42857142857144));

    // 初始：计数文本为 1，State 只创建了一次
    expect(find.text('计数1'), findsOneWidget);
    expect(stateCreations, 1);

    // 改变父宽度（列数由 2 变为 3），重新 pump
    await tester.pumpWidget(buildGrid(700));
    await tester.pump();

    // State 未被销毁重建：计数文本仍为 1，且 State 创建次数未增加
    // （若子项被销毁重建，onStateCreated 会再次触发，stateCreations 会变为 2）
    expect(find.text('计数1'), findsOneWidget);
    expect(stateCreations, 1);
  });
}

class _CountingCounter extends StatefulWidget {
  const _CountingCounter({
    super.key,
    required this.initialCount,
    this.onStateCreated,
  });

  final int initialCount;
  final VoidCallback? onStateCreated;

  @override
  State<_CountingCounter> createState() => _CountingCounterState();
}

class _CountingCounterState extends State<_CountingCounter> {
  late int _count = widget.initialCount;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Text('计数$_count');
  }
}
