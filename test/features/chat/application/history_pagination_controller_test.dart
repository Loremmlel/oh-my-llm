import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
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
      expect(repo.countCallCount, 1);
    });

    test('loadInitial 空串 keyword 下 hasAnyConversations 跟随 totalItems', () {
      final repo = FakeHistoryRepository(pages: const [[]], countResult: 0);
      final c = createContainer(repo);

      c.read(historyPaginationProvider.notifier).loadInitial();

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isFalse);
      expect(s.totalItems, 0);
      expect(s.totalPages, 0);
    });

    test('loadInitial 带 keyword 时 hasAnyConversations 恒为 true', () {
      final repo = FakeHistoryRepository(pages: const [[]], countResult: 0);
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

      // 重置计数，只关注 setPageSize 本身
      repo.countCallCount = 0;
      c.read(historyPaginationProvider.notifier).setPageSize(10);

      final s = c.read(historyPaginationProvider);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
      expect(repo.countCallCount, 1); // loadInitial 内部 count
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
      c.read(historyPaginationProvider.notifier).loadInitial();

      c.read(historyPaginationProvider.notifier).afterRename('a', '新名字');

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.firstWhere((e) => e.id == 'a').title, '新名字');
      expect(s.conversations.firstWhere((e) => e.id == 'b').title, '对话 b');
    });

    test('afterDelete 当前页仍有条目时只做本地移除', () {
      final repo = FakeHistoryRepository(
        pages: [
          [summary('a'), summary('b'), summary('c')],
        ],
        sequenceCounts: [3, 2],
      );
      final c = createContainer(repo);
      c.read(historyPaginationProvider.notifier).loadInitial();
      final pagedBefore = repo.pagedCalls.length;

      c.read(historyPaginationProvider.notifier).afterDelete({'b'});

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((item) => item.id), ['a', 'c']);
      expect(s.totalItems, 2);
      expect(s.currentPage, 1);
      expect(repo.pagedCalls.length, pagedBefore);
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
