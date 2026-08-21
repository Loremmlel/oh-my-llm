import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/pagination/app_pagination_bar.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

import '../../../helpers/async/widget_test_animation.dart';

/// 用固定父级宽度挂载分页栏，避免整窗平台标签影响宽/窄模式判定。
Future<void> _pumpBar(
  WidgetTester tester, {
  required double width,
  required AppPaginationState state,
  ValueChanged<int>? onPageChanged,
  ValueChanged<int>? onPageSizeChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: AppPaginationBar(
            state: state,
            onPageChanged: onPageChanged ?? (_) {},
            onPageSizeChanged: onPageSizeChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

/// 定位跳转输入框（label 为「页码」的 TextField）。
Finder _jumpField() =>
    find.ancestor(of: find.text('页码'), matching: find.byType(TextField));

void main() {
  group('AppPaginationBar', () {
    testWidgets('宽父约束下显示总数、页码序列与跳转入口', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      expect(find.text('共 100 条 · 1/5 页'), findsOneWidget);
      // 5 页不超过折叠阈值，页码 1..5 全部可见。
      expect(find.text('3'), findsOneWidget);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(find.byTooltip('下一页'), findsOneWidget);
      expect(tester.widget<TextField>(_jumpField()), isA<TextField>());
      expect(find.text('跳转'), findsOneWidget);
      expect(changedPage, -1);
    });

    testWidgets('窄父约束下收缩为翻页按钮、页码概览与容量', (tester) async {
      await _pumpBar(
        tester,
        width: 320,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
      );

      // 紧凑模式不渲染页码按钮序列与跳转入口。
      expect(find.text('3'), findsNothing);
      expect(find.text('共 100 条 · 1/5 页'), findsNothing);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(find.byTooltip('下一页'), findsOneWidget);
      expect(find.textContaining('1/5'), findsOneWidget);
      expect(find.text('每页'), findsOneWidget);
      expect(find.text('跳转'), findsNothing);
    });

    testWidgets('busy 期间禁用全部翻页交互', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
          isBusy: true,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      await tester.tap(find.byTooltip('下一页'));
      await tester.tap(find.text('3'), warnIfMissed: false);
      await tester.tap(find.text('跳转'));

      expect(changedPage, -1);
    });

    testWidgets('选择新的每页容量时回调容量变更', (tester) async {
      var changedSize = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageSizeChanged: (size) => changedSize = size,
      );

      await tester.tap(find.text('每页'), warnIfMissed: false);
      await settleOverlayTransition(tester);
      await tester.tap(find.text('50'));
      await settleOverlayTransition(tester);

      expect(changedSize, 50);
    });

    testWidgets('点击其他页码时回调目标页', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      await tester.tap(find.text('3'));

      expect(changedPage, 3);
    });

    testWidgets('点击当前页页码不重复回调', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 3,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      // 当前页按钮由 AbsorbPointer 吸收点击，tap 落空属预期。
      await tester.tap(find.text('3'), warnIfMissed: false);

      expect(changedPage, -1);
    });

    testWidgets('跳转到合法页码后回调并清空输入', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      await tester.enterText(_jumpField(), '4');
      await tester.tap(find.text('跳转'));

      expect(changedPage, 4);
      expect(tester.widget<TextField>(_jumpField()).controller?.text, isEmpty);
    });

    testWidgets('空跳转内容不触发页码回调', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      await tester.tap(find.text('跳转'));

      expect(changedPage, -1);
    });

    testWidgets('跳转越界页码夹取到最后一页', (tester) async {
      var changedPage = -1;
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
        onPageChanged: (page) => changedPage = page,
      );

      await tester.enterText(_jumpField(), '999');
      await tester.tap(find.text('跳转'));

      expect(changedPage, 5);
    });

    testWidgets('总页数为零时不渲染任何翻页控件', (tester) async {
      await _pumpBar(tester, width: 800, state: const AppPaginationState());

      expect(find.byTooltip('下一页'), findsNothing);
      expect(find.text('每页'), findsNothing);
      expect(find.text('跳转'), findsNothing);
    });

    testWidgets('翻页按钮保持 48 逻辑像素命中区域', (tester) async {
      await _pumpBar(
        tester,
        width: 800,
        state: const AppPaginationState(
          currentPage: 1,
          pageSize: 20,
          totalItems: 100,
        ),
      );

      final prevSize = tester.getSize(find.byTooltip('上一页'));
      final nextSize = tester.getSize(find.byTooltip('下一页'));
      expect(prevSize.width, greaterThanOrEqualTo(48));
      expect(prevSize.height, greaterThanOrEqualTo(48));
      expect(nextSize.width, greaterThanOrEqualTo(48));
      expect(nextSize.height, greaterThanOrEqualTo(48));
    });
  });
}
