import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/history/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

import '../../../../helpers/chat/fake_history_repository.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    addTearDown(database.close);
  });

  ProviderContainer createContainer(FakeHistoryRepository repo) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatConversationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  ChatConversationSummary summary(String id) => ChatConversationSummary(
    id: id,
    title: '对话 $id',
    updatedAt: DateTime(2026, 6, 1).add(const Duration(minutes: 1)),
  );

  group('HistoryPaginationController', () {
    test('loadRoute 默认加载第 1 页并写入 count 与 totalItems', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 10,
      );
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, hasLength(1));
      expect(s.totalItems, 10);
      expect(s.totalPages, 1);
      expect(s.currentPage, 1);
      expect(repo.countCallCount, 1);
    });

    test('loadRoute 空串关键词下 hasAnyConversations 跟随 totalItems', () {
      final repo = FakeHistoryRepository(pages: const [[]], countResult: 0);
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isFalse);
      expect(s.totalItems, 0);
      expect(s.totalPages, 0);
    });

    test('loadRoute 带关键词时 hasAnyConversations 恒为 true', () {
      final repo = FakeHistoryRepository(pages: const [[]], countResult: 0);
      final c = createContainer(repo);

      c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: 'foo');

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isTrue);
    });

    test('goToPage 跳转到目标页并正确计算 offset', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // page 1 (首次 loadRoute)
          [summary('b'), summary('c')], // page 3 (goToPage 3)
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      repo.countCallCount = 0; // 只关注翻页后的调用

      c.read(historyPaginationProvider.notifier).goToPage(3);

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 3);
      expect(repo.pagedCalls.last.offset, 40); // (3-1) * 20
      expect(repo.countCallCount, 1); // goToPage 刷新总数
    });

    test('goToPage 夹取越界页码（<1 视为 1，>totalPages 视为 totalPages）', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
          [summary('c')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).goToPage(99);
      expect(c.read(historyPaginationProvider).currentPage, 3); // ceil(50/20)

      c.read(historyPaginationProvider.notifier).goToPage(0);
      expect(c.read(historyPaginationProvider).currentPage, 1);

      c.read(historyPaginationProvider.notifier).goToPage(-5);
      expect(c.read(historyPaginationProvider).currentPage, 1);
    });

    test('goToPage 同一页直接返回', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      final pagedBefore = repo.pagedCalls.length;

      c.read(historyPaginationProvider.notifier).goToPage(1);

      expect(repo.pagedCalls.length, pagedBefore); // 不会重新拉取
    });

    test('next / prev 在边界处不越界', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // page 1
          [summary('b')], // page 2
          [summary('c')], // page 3
        ],
        countResult: 60,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      // 在第 1 调用 prev，应仍为 1。
      c.read(historyPaginationProvider.notifier).prev();
      expect(c.read(historyPaginationProvider).currentPage, 1);

      // 连跳 3 次到最后一页
      c.read(historyPaginationProvider.notifier).next();
      c.read(historyPaginationProvider.notifier).next();
      c.read(historyPaginationProvider.notifier).next();
      c.read(historyPaginationProvider.notifier).next(); // 越界守卫
      expect(c.read(historyPaginationProvider).currentPage, 3);

      c.read(historyPaginationProvider.notifier).next(); // 仍不超过 last
      expect(c.read(historyPaginationProvider).currentPage, 3);
    });

    test('first / last 跳转边界', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
          [summary('c')],
        ],
        countResult: 60,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).last();
      expect(c.read(historyPaginationProvider).currentPage, 3);

      c.read(historyPaginationProvider.notifier).first();
      expect(c.read(historyPaginationProvider).currentPage, 1);
    });

    test('setPageSize 重置到第 1 页并更新 totalPages', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(c.read(historyPaginationProvider).currentPage, 3);

      // 重置计数，只关注 setPageSize 本身
      repo.countCallCount = 0;
      c.read(historyPaginationProvider.notifier).setPageSize(10);

      final s = c.read(historyPaginationProvider);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
      expect(repo.countCallCount, 1); // loadRoute 内部 count
    });

    test('setPageSize 非法值不生效', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      final sizeBefore = c.read(historyPaginationProvider).pageSize;

      c.read(historyPaginationProvider.notifier).setPageSize(999);

      expect(c.read(historyPaginationProvider).pageSize, sizeBefore);
    });

    test('setKeyword 重置到第 1 页并刷新 count', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 30,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      c.read(historyPaginationProvider.notifier).goToPage(2);
      expect(c.read(historyPaginationProvider).currentPage, 2);

      repo.countCallCount = 0;
      c.read(historyPaginationProvider.notifier).setKeyword('新关键词');

      final s = c.read(historyPaginationProvider);
      expect(s.keyword, '新关键词');
      expect(s.currentPage, 1);
      expect(repo.countCallCount, 1);
    });

    test('setKeyword 空串旧值下幂等', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 10,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      final countBefore = repo.countCallCount;

      c
          .read(historyPaginationProvider.notifier)
          .setKeyword('   '); // trim 后为 ''

      expect(repo.countCallCount, countBefore); // 不再重新调 count
    });

    test('afterRename 只更新当前页匹配项', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a'), summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).afterRename('a', '新名字');

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.firstWhere((e) => e.id == 'a').title, '新名字');
      expect(s.conversations.firstWhere((e) => e.id == 'b').title, '对话 b');
    });

    test('afterDelete 按数据库真实结果补齐当前页窗口', () {
      // 40 条、每页 20：删除第 1 页首条后，重拉的第 1 页应仍为 20 条
      // （原第 2 页首项补入），下一页从原第 22 条开始不漏项。
      final all = List.generate(40, (i) => summary('item$i'));
      final repo = FakeHistoryRepository(
        pages: [
          all.sublist(0, 20), // 首次 loadRoute：原第 1 页
          [...all.sublist(1, 20), all[20]], // 删除后补页的第 1 页（模拟数据库真实分布）
          all.sublist(21, 40), // 新的第 2 页：19 条
        ],
        sequenceCounts: [40, 39, 39],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      final pagedBefore = repo.pagedCalls.length;

      c.read(historyPaginationProvider.notifier).afterDelete({'item0'});

      final s = c.read(historyPaginationProvider);
      expect(
        repo.pagedCalls.length,
        pagedBefore + 1,
        reason: '删除后必须按真实结果重拉当前窗口',
      );
      expect(repo.pagedCalls.last.offset, 0);
      expect(s.totalItems, 39);
      expect(s.currentPage, 1);
      expect(s.conversations, hasLength(20));
      expect(s.conversations.last.id, 'item20');
      expect(s.errorMessage, isNull);

      // 下一页不漏项：offset 从第 21 条开始。
      c.read(historyPaginationProvider.notifier).next();
      expect(repo.pagedCalls.last.offset, 20);
      final nextPage = c.read(historyPaginationProvider);
      expect(
        nextPage.conversations.map((e) => e.id),
        all.sublist(21, 40).map((e) => e.id),
      );
      expect(nextPage.hasNext, isFalse);
    });

    test('搜索态 rename 使条目退出匹配时重拉并修正总数', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a'), summary('b')], // 关键词「旧」命中 a、b
          [summary('a')], // b 改名后不再命中
        ],
        sequenceCounts: [2, 1],
      );
      final c = createContainer(repo);
      c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: '旧');
      final pagedBefore = repo.pagedCalls.length;

      c.read(historyPaginationProvider.notifier).afterRename('b', '新名字');

      final s = c.read(historyPaginationProvider);
      expect(
        repo.pagedCalls.length,
        pagedBefore + 1,
        reason: '搜索态 rename 必须重新查询',
      );
      expect(s.conversations.map((e) => e.id), ['a']);
      expect(s.totalItems, 1);
      expect(s.currentPage, 1);
    });

    test('搜索态 rename 使条目进入匹配时同样按查询结果呈现', () {
      final renamed = summary('b').copyWith(title: '新名字');
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // 关键词「新」只命中 a
          [summary('a'), renamed], // b 改名后进入匹配
        ],
        sequenceCounts: [1, 2],
      );
      final c = createContainer(repo);
      c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: '新');
      final pagedBefore = repo.pagedCalls.length;

      c.read(historyPaginationProvider.notifier).afterRename('b', '新名字');

      final s = c.read(historyPaginationProvider);
      expect(repo.pagedCalls.length, pagedBefore + 1);
      expect(s.conversations.map((e) => e.id), ['a', 'b']);
      expect(s.totalItems, 2);
    });

    test('afterDelete 全部删尽会清空并进入空库状态', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        sequenceCounts: [1, 0],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).afterDelete({'a'});

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, isEmpty);
      expect(s.totalItems, 0);
      expect(s.hasAnyConversations, isFalse);
    });

    test('hasPrevious / hasNext 派生正确', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
          [summary('c')],
        ],
        countResult: 60,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      // page 1
      expect(c.read(historyPaginationProvider).hasPrevious, isFalse);
      expect(c.read(historyPaginationProvider).hasNext, isTrue);

      c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(c.read(historyPaginationProvider).hasPrevious, isTrue);
      expect(c.read(historyPaginationProvider).hasNext, isFalse);
    });

    test('loadRoute 使用 route 页码、容量与关键词查询', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // 首次 loadRoute
          [summary('b')], // loadRoute 第 2 页
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 2, pageSize: 10, keyword: '关键词');

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 2);
      expect(s.pageSize, 10);
      expect(s.keyword, '关键词');
      expect(s.totalItems, 50);
      expect(s.isInitialized, isTrue);
      expect(s.errorMessage, isNull);
      expect(repo.pagedCalls.last.keyword, '关键词');
      expect(repo.pagedCalls.last.limit, 10);
      expect(repo.pagedCalls.last.offset, 10);
    });

    test('loadRoute 关键词先 trim 再生效', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 10,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).loadRoute(keyword: '  空格  ');

      expect(c.read(historyPaginationProvider).keyword, '空格');
      expect(repo.pagedCalls.last.keyword, '空格');
    });

    test('loadRoute 非法容量回退持久化偏好', () {
      preferences.setInt('app.feature.history.page_size', 10);
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).loadRoute(pageSize: 999);

      expect(c.read(historyPaginationProvider).pageSize, 10);
    });

    test('loadRoute 页码越界夹取到查询后的真实末页', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      // 数据变化后真实末页为 3，越界请求夹取到第 3 页。
      c.read(historyPaginationProvider.notifier).loadRoute(page: 99);

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 3);
      expect(repo.pagedCalls.last.offset, 40);
    });

    test('loadRoute 总数为 0 时页码归一为 1', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          const [],
        ],
        sequenceCounts: [10, 0],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).loadRoute(page: 5);

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 1);
      expect(s.totalItems, 0);
      expect(s.conversations, isEmpty);
    });

    test('count 或 load 抛错时保留旧窗口内容并进入错误态', () {
      for (final inject in <void Function(FakeHistoryRepository)>[
        (repo) => repo.throwOnCount = StateError('count 失败'),
        (repo) => repo.throwOnLoad = StateError('load 失败'),
      ]) {
        final repo = FakeHistoryRepository(
          pages: [
            [summary('a')], // 首次 loadRoute 正常
          ],
          countResult: 10,
        );
        final c = createContainer(repo);
        c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

        inject(repo);
        c.read(historyPaginationProvider.notifier).loadRoute(page: 2);

        final s = c.read(historyPaginationProvider);
        expect(s.conversations.map((e) => e.id), ['a'], reason: '旧内容保留');
        expect(s.errorMessage, isNotNull);
        expect(s.isInitialized, isTrue);
        expect(s.currentPage, 1);
      }
    });

    test('错误后重试成功清除错误并载入目标窗口', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // 首次 loadRoute
          [summary('b')], // 重试成功后的第 2 页
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);
      repo.throwOnLoad = StateError('boom');
      c.read(historyPaginationProvider.notifier).loadRoute(page: 2);
      expect(c.read(historyPaginationProvider).errorMessage, isNotNull);

      repo.throwOnLoad = null;
      c.read(historyPaginationProvider.notifier).loadRoute(page: 2);

      final s = c.read(historyPaginationProvider);
      expect(s.errorMessage, isNull);
      expect(s.currentPage, 2);
      expect(s.conversations.map((e) => e.id), ['b']);
    });

    test('setPageSize 将所选容量回写持久化偏好', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadRoute(page: 1);

      c.read(historyPaginationProvider.notifier).setPageSize(10);

      expect(preferences.getInt('app.feature.history.page_size'), 10);
    });
  });
}
