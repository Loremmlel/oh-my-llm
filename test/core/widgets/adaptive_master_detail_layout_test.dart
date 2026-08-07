import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/adaptive_master_detail_layout.dart';

/// 以指定父宽度挂载布局；宽分支同时渲染 master 与 detail，紧凑分支只渲染 compactChild。
Future<void> _pumpLayout(
  WidgetTester tester,
  double parentWidth, {
  double breakpoint = AppBreakpoints.contentMasterDetail,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: parentWidth,
          child: AdaptiveMasterDetailLayout(
            breakpoint: breakpoint,
            compactChild: const Text('紧凑内容'),
            master: const Text('主栏'),
            detail: const Text('详情'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('默认断点：839 显示紧凑子项', (tester) async {
    await _pumpLayout(tester, 839);
    expect(find.text('紧凑内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认断点：840 等号进入双栏', (tester) async {
    await _pumpLayout(tester, 840);
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认断点：841 稳定双栏', (tester) async {
    await _pumpLayout(tester, 841);
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可注入断点：dialogMasterDetail 下 759 紧凑、760 双栏', (tester) async {
    await _pumpLayout(
      tester,
      759,
      breakpoint: AppBreakpoints.dialogMasterDetail,
    );
    expect(find.text('紧凑内容'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpLayout(
      tester,
      760,
      breakpoint: AppBreakpoints.dialogMasterDetail,
    );
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
