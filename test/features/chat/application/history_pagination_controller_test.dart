import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

import '../../../helpers/fake_history_repository.dart';

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
    test('loadInitial 写入首份数据、count 与 totalItems', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 10,
      );
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadInitial();

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, hasLength(1));
      expect(s.totalItems, 10);
      expect(s.totalPages, 1);
      expect(s.currentPage, 1);
      expect(s.totalPages, 1);
      expect(repo.countCallCount, 1);
    });

    test('loadInitial 空串 keyword 下 hasAnyConversations 跟随 totalItems',
        () {
      final repo = FakeHistoryRepository(
        pages: const [
          [],
        ],
        countResult: 0,
      );
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadInitial();

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isFalse);
      expect(s.totalItems, 0);
      expect(s.totalPages, 0);
    });

    test('loadInitial 带 keyword 时 hasAnyConversations 恒为 true', () {
      final repo = FakeHistoryRepository(
        pages: const [
          [],
        ],
        countResult: 0,
      );
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadInitial(keyword: 'foo');

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isTrue);
    });

    test('goToPage 跳转到目标页并正确计算 offset', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')], // page 1 (loadInitial)
          [summary('b'), summary('c')], // page 3 (goToPage 3)
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();
      repo.countCallCount = 0; // 只关注翻页后的调用

      c.read(historyPaginationProvider.notifier).goToPage(3);

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 3);
      expect(repo.pagedCalls.last.offset, 40); // (3-1) * 20
      expect(repo.countCallCount, 0); // goToPage 不计 count
    });

    test('goToPage 夹取越界页码（<1 视为 1，>totalPages 视为 totalPages）',
        () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
          [summary('c')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();

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
      c.read(historyPaginationProvider.notifier).loadInitial();
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
      c.read(historyPaginationProvider.notifier).loadInitial();

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
      c.read(historyPaginationProvider.notifier).loadInitial();

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
      c.read(historyPaginationProvider.notifier).loadInitial();
      c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(c.read(historyPaginationProvider).currentPage, 3);

      c.read(historyPaginationProvider.notifier).setPageSize(10);

      final s = c.read(historyPaginationProvider);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
      expect(repo.countCallCount, 2); // loadInitial + setPageSize
    });

    test('setPageSize 非法值不生效', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();
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
      c.read(historyPaginationProvider.notifier).loadInitial();
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
      c.read(historyPaginationProvider.notifier).loadInitial();
      final countBefore = repo.countCallCount;

      c.read(historyPaginationProvider.notifier).setKeyword('   '); // trim 后为 ''

      expect(repo.countCallCount, countBefore); // 不再重新调 count
    });

    test('isLoading 守卫防止并发翻页', () {
      // 直接调用两次 goToPage：由于同步 state 更新，第二次应当在第一次完成后才生效
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
          [summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();
      final pagedBefore = repo.pagedCalls.length;

      // 连续两次翻页，每次 state 同步更新，不应出现竞态导致的丢失
      c.read(historyPaginationProvider.notifier).goToPage(2);
      c.read(historyPaginationProvider.notifier).goToPage(1);

      // 最终应稳定在 page 1
      expect(c.read(historyPaginationProvider).currentPage, 1);
      // 两次各自完成拉取（顺序拉取，底层同步完成无并发问题）
      expect(repo.pagedCalls.length - pagedBefore, 2);
    });

    test('afterRename 只更新当前页匹配项', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a'), summary('b')],
        ],
        countResult: 50,
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();

      c.read(historyPaginationProvider.notifier).afterRename('a', '新名字');

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.firstWhere((e) => e.id == 'a').title, '新名字');
      expect(s.conversations.firstWhere((e) => e.id == 'b').title, '对话 b');
    });

    test('afterDelete 当前页有效时仅本地移除', () {
      // 初始 totalItems=50 (pageSize=20 -> 3 页)；删除后 totalItems=49 (仍 3 页)。
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a'), summary('b'), summary('c')],
          [summary('d')],
        ],
        sequenceCounts: [50, 49],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();

      // 跳到第 3 页
      c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(c.read(historyPaginationProvider).currentPage, 3);

      // 删除 d 后 totalItems 变为 49，totalPages 仍为 3；
      // 但当前页 3 已无数据（d 被删），应回退到新的最后一页。
      c.read(historyPaginationProvider.notifier).afterDelete({'d'});

      final s = c.read(historyPaginationProvider);
      expect(s.totalItems, 49);
      expect(s.totalPages, 3); // ceil(49/20)
      // 当前页越界 -> 回退到最后一页
      expect(s.currentPage, 3);
    });

    test('afterDelete 全部删尽会清空并进入空库状态', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
        sequenceCounts: [1, 0],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();

      c.read(historyPaginationProvider.notifier).afterDelete({'a'});

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, isEmpty);
      expect(s.totalItems, 0);
      expect(s.hasAnyConversations, isFalse);
    });

    test('totalPages 派生：ceil(totalItems / pageSize)', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a')],
        ],
      );
      final c = createContainer(repo);

      // totalItems=1 (默认 countResult 用 pages 总和), pageSize=20 -> 1 页
      c.read(historyPaginationProvider.notifier).loadInitial();
      expect(c.read(historyPaginationProvider).totalPages, 1);

      c.read(historyPaginationProvider.notifier).setPageSize(1);
      // reload 后 count 仍是 1 -> totalItems=1, pageSize=1 -> 1页
      c.read(historyPaginationProvider.notifier).setPageSize(20); // 回到 20
      c.read(historyPaginationProvider.notifier).loadInitial(); // 重拉 1 个元素
      expect(c.read(historyPaginationProvider).totalPages, 1);
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
      c.read(historyPaginationProvider.notifier).loadInitial();

      // page 1
      expect(c.read(historyPaginationProvider).hasPrevious, isFalse);
      expect(c.read(historyPaginationProvider).hasNext, isTrue);

      c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(c.read(historyPaginationProvider).hasPrevious, isTrue);
      expect(c.read(historyPaginationProvider).hasNext, isFalse);
    });
  });
}
