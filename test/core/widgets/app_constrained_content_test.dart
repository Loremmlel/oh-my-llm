import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/app_constrained_content.dart';

/// 以指定外层宽度挂载 [AppConstrainedContent]，内层 LayoutBuilder 捕获 child
/// 实际拿到的最大宽度并返回。
Future<double> _observedMaxWidth(
  WidgetTester tester,
  double outerWidth, {
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  double? maxWidth;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: outerWidth,
            child: AppConstrainedContent(
              padding: padding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  maxWidth = constraints.maxWidth;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return maxWidth!;
}

void main() {
  testWidgets('1400 外层时 child 获得可读限宽 720', (tester) async {
    expect(await _observedMaxWidth(tester, 1400), 720);
  });

  testWidgets('390 外层左右各 16 padding 时 child 获得 358', (tester) async {
    expect(
      await _observedMaxWidth(
        tester,
        390,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      358,
    );
  });
}
