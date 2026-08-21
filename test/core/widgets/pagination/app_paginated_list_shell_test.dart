import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/pagination/app_paginated_list_shell.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_bar.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

/// 收集外壳回调与 bodyBuilder 交出的滚动控制器。
class _ShellHarness {
  ScrollController? bodyScrollController;
  int pageChangedTo = -1;
  int pageSizeChangedTo = -1;
  int retryCount = 0;
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppPaginationState state,
  Object? pageIdentity,
  bool initialLoading = false,
  String? error,
  VoidCallback? onRetry,
  Widget? header,
  _ShellHarness? harness,
}) async {
  final shellHarness = harness ?? _ShellHarness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppPaginatedListShell(
          header: header,
          paginationState: state,
          pageIdentity: pageIdentity,
          initialLoading: initialLoading,
          error: error,
          onRetry: onRetry,
          onPageChanged: (page) => shellHarness.pageChangedTo = page,
          onPageSizeChanged: (size) => shellHarness.pageSizeChangedTo = size,
          bodyBuilder: (context, scrollController) {
            shellHarness.bodyScrollController = scrollController;
            return ListView.builder(
              controller: scrollController,
              itemCount: 60,
              itemBuilder: (_, index) =>
                  SizedBox(height: 50, child: Text('条目 $index')),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  const visibleState = AppPaginationState(
    currentPage: 1,
    pageSize: 20,
    totalItems: 100,
  );

  group('AppPaginatedListShell', () {
    testWidgets('header 与固定底部分页栏同时可见', (tester) async {
      await _pumpShell(tester, state: visibleState, header: const Text('顶部标题'));

      expect(find.text('顶部标题'), findsOneWidget);
      expect(find.byType(AppPaginationBar), findsOneWidget);
      expect(find.text('共 100 条 · 1/5 页'), findsOneWidget);
    });

    testWidgets('正文独立滚动时分页栏保持在原位不被滚走', (tester) async {
      final harness = _ShellHarness();
      await _pumpShell(tester, state: visibleState, harness: harness);

      expect(find.text('条目 0'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();

      expect(harness.bodyScrollController!.offset, 500);
      // 正文滚过一屏后分页栏仍可命中，说明它固定在底部、不参与正文滚动。
      expect(find.text('共 100 条 · 1/5 页').hitTestable(), findsOneWidget);
    });

    testWidgets('初次加载时显示加载指示且不渲染正文', (tester) async {
      await _pumpShell(tester, state: visibleState, initialLoading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('条目 0'), findsNothing);
    });

    testWidgets('已有正文时出错保留内容并展示内联错误与重试', (tester) async {
      var retryCount = 0;
      await _pumpShell(
        tester,
        state: visibleState,
        error: '加载失败',
        onRetry: () => retryCount++,
      );

      // 旧内容不清空，错误以内联区块呈现。
      expect(find.text('条目 0'), findsOneWidget);
      expect(find.text('加载失败'), findsOneWidget);

      await tester.tap(find.text('重试'));
      expect(retryCount, 1);
    });

    testWidgets('分页栏回调透传给外壳回调', (tester) async {
      final harness = _ShellHarness();
      await _pumpShell(tester, state: visibleState, harness: harness);

      await tester.tap(find.byTooltip('下一页'));

      expect(harness.pageChangedTo, 2);
    });

    testWidgets('pageIdentity 变化后正文回到顶部', (tester) async {
      final harness = _ShellHarness();
      await _pumpShell(
        tester,
        state: visibleState,
        pageIdentity: 'collection=a&page=1',
        harness: harness,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(harness.bodyScrollController!.offset, 400);

      await _pumpShell(
        tester,
        state: const AppPaginationState(
          currentPage: 2,
          pageSize: 20,
          totalItems: 100,
        ),
        pageIdentity: 'collection=a&page=2',
        harness: harness,
      );

      expect(harness.bodyScrollController!.offset, 0);
    });

    testWidgets('相同 pageIdentity 的等价重建不误清滚动位置', (tester) async {
      final harness = _ShellHarness();
      await _pumpShell(
        tester,
        state: visibleState,
        pageIdentity: 'collection=a&page=1',
        harness: harness,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(harness.bodyScrollController!.offset, 400);

      // 模拟详情 push/pop 后父级重组：widget 实例全新但 identity 未变。
      await _pumpShell(
        tester,
        state: visibleState,
        pageIdentity: 'collection=a&page=1',
        harness: harness,
      );

      expect(harness.bodyScrollController!.offset, 400);
    });
  });
}
