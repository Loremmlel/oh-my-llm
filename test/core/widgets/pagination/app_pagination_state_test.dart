import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';

void main() {
  test('分页状态推导总页数、当前页和相邻关系', () {
    final cases =
        <
          ({
            int page,
            int pageSize,
            int totalItems,
            int totalPages,
            int currentPage,
            bool previous,
            bool next,
          })
        >[
          (
            page: 3,
            pageSize: 20,
            totalItems: 0,
            totalPages: 0,
            currentPage: 1,
            previous: false,
            next: false,
          ),
          (
            page: -3,
            pageSize: 20,
            totalItems: 60,
            totalPages: 3,
            currentPage: 1,
            previous: false,
            next: true,
          ),
          (
            page: 2,
            pageSize: 20,
            totalItems: 60,
            totalPages: 3,
            currentPage: 2,
            previous: true,
            next: true,
          ),
          (
            page: 42,
            pageSize: 20,
            totalItems: 60,
            totalPages: 3,
            currentPage: 3,
            previous: true,
            next: false,
          ),
        ];

    for (final entry in cases) {
      final state = AppPaginationState(
        currentPage: entry.page,
        pageSize: entry.pageSize,
        totalItems: entry.totalItems,
      );
      expect(state.totalPages, entry.totalPages, reason: '$entry');
      expect(state.currentPage, entry.currentPage, reason: '$entry');
      expect(state.hasPrevious, entry.previous, reason: '$entry');
      expect(state.hasNext, entry.next, reason: '$entry');
    }
  });

  test('分页函数按边界进位并把页码夹取到有效范围', () {
    for (final (items, size, expected) in [
      (0, 20, 0),
      (5, 20, 1),
      (40, 20, 2),
      (41, 20, 3),
      (100, 0, 0),
      (100, -1, 0),
    ]) {
      expect(
        totalPagesForItems(items, size),
        expected,
        reason: 'items=$items size=$size',
      );
    }
    for (final (page, totalPages, expected) in [
      (-2, 3, 1),
      (2, 3, 2),
      (99, 3, 3),
      (5, 0, 1),
    ]) {
      expect(
        clampPageToValidRange(page, totalPages),
        expected,
        reason: 'page=$page totalPages=$totalPages',
      );
    }
  });

  test('状态构造器与共享夹取函数在参数网格上保持一致', () {
    for (final (pageSize, totalItems) in [
      (20, 0),
      (20, 5),
      (20, 40),
      (20, 41),
      (10, 1),
    ]) {
      final totalPages = totalPagesForItems(totalItems, pageSize);
      for (final page in [-3, 0, 1, 2, 3, 99]) {
        expect(
          AppPaginationState(
            currentPage: page,
            pageSize: pageSize,
            totalItems: totalItems,
          ).currentPage,
          clampPageToValidRange(page, totalPages),
          reason: 'pageSize=$pageSize totalItems=$totalItems page=$page',
        );
      }
    }
  });

  test('可见页码按完整、单侧省略和双侧省略三类布局生成', () {
    final cases = <({int total, int current, List<int?> expected})>[
      (total: 7, current: 4, expected: [1, 2, 3, 4, 5, 6, 7]),
      (total: 8, current: 4, expected: [1, 2, 3, 4, 5, null, 7, 8]),
      (total: 8, current: 7, expected: [1, 2, null, 6, 7, 8]),
      (total: 100, current: 1, expected: [1, 2, null, 99, 100]),
      (
        total: 100,
        current: 50,
        expected: [1, 2, null, 49, 50, 51, null, 99, 100],
      ),
      (total: 0, current: 1, expected: []),
      (total: -5, current: 1, expected: []),
    ];

    for (final entry in cases) {
      expect(
        resolveVisiblePageNumbers(
          entry.total,
          entry.current,
        ).map((item) => item.page),
        entry.expected,
        reason: '$entry',
      );
    }
  });
}
