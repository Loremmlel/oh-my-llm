import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

void main() {
  group('AppPaginationState', () {
    test('总条数为 0 时总页数为 0 且当前页归一为 1', () {
      const state = AppPaginationState(
        currentPage: 3,
        pageSize: 20,
        totalItems: 0,
      );

      expect(state.totalPages, 0);
      expect(state.currentPage, 1);
    });

    test('不足一页的数据推导出单页', () {
      const state = AppPaginationState(pageSize: 20, totalItems: 5);

      expect(state.totalPages, 1);
    });

    test('整除与进位边界推导出正确的总页数', () {
      // 140/20 恰为 7 页；141/20 进位到 8 页；2000/20 为 100 页。
      expect(AppPaginationState(pageSize: 20, totalItems: 140).totalPages, 7);
      expect(AppPaginationState(pageSize: 20, totalItems: 141).totalPages, 8);
      expect(
        AppPaginationState(pageSize: 20, totalItems: 2000).totalPages,
        100,
      );
    });

    test('当前页小于 1 时夹取为 1', () {
      const state = AppPaginationState(
        currentPage: -3,
        pageSize: 20,
        totalItems: 100,
      );

      expect(state.currentPage, 1);
    });

    test('当前页超出总页数时夹取为最后一页', () {
      const state = AppPaginationState(
        currentPage: 42,
        pageSize: 20,
        totalItems: 60,
      );

      expect(state.totalPages, 3);
      expect(state.currentPage, 3);
    });

    test('hasPrevious 与 hasNext 描述当前页的邻接关系', () {
      const first = AppPaginationState(
        currentPage: 1,
        pageSize: 20,
        totalItems: 60,
      );
      expect(first.hasPrevious, isFalse);
      expect(first.hasNext, isTrue);

      const middle = AppPaginationState(
        currentPage: 2,
        pageSize: 20,
        totalItems: 60,
      );
      expect(middle.hasPrevious, isTrue);
      expect(middle.hasNext, isTrue);

      const last = AppPaginationState(
        currentPage: 3,
        pageSize: 20,
        totalItems: 60,
      );
      expect(last.hasPrevious, isTrue);
      expect(last.hasNext, isFalse);
    });
  });

  group('resolveVisiblePageNumbers', () {
    test('总页数不超过 7 时完整显示所有页码且无省略', () {
      final pages = resolveVisiblePageNumbers(7, 4);

      expect(pages.map((item) => item.page), [1, 2, 3, 4, 5, 6, 7]);
      expect(pages.any((item) => item.isEllipsis), isFalse);
    });

    test('8 页且当前页居中时折叠为两端窗口加一个省略', () {
      final pages = resolveVisiblePageNumbers(8, 4);

      // 手工推演：首 2 页 {1,2} + 当前 ±1 {3,4,5} + 末 2 页 {7,8}，
      // 5 与 7 之间插入省略。
      expect(pages.map((item) => item.page), [1, 2, 3, 4, 5, null, 7, 8]);
      expect(pages.where((item) => item.isEllipsis).length, 1);
    });

    test('8 页且当前页邻近末尾时当前窗口与末页合并去重', () {
      final pages = resolveVisiblePageNumbers(8, 7);

      // {1,2} ∪ {6,7,8} ∪ {7,8} → 1,2,…,6,7,8。
      expect(pages.map((item) => item.page), [1, 2, null, 6, 7, 8]);
    });

    test('大量页码且停在首页时仅末尾出现省略', () {
      final pages = resolveVisiblePageNumbers(100, 1);

      expect(pages.map((item) => item.page), [1, 2, null, 99, 100]);
    });

    test('大量页码且当前页居中时两侧均出现省略', () {
      final pages = resolveVisiblePageNumbers(100, 50);

      expect(pages.map((item) => item.page), [
        1,
        2,
        null,
        49,
        50,
        51,
        null,
        99,
        100,
      ]);
    });

    test('总页数非正时返回空列表而不是抛出异常', () {
      expect(resolveVisiblePageNumbers(0, 1), isEmpty);
      expect(resolveVisiblePageNumbers(-5, 1), isEmpty);
    });
  });
}
