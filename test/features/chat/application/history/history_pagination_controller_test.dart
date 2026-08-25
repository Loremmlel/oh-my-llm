import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/history/history_pagination_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/domain/history_pagination_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

import '../../../../helpers/chat/controllable_history_page_query.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  ProviderContainer createContainer(ControllableHistoryPageQuery query) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        historyPageQueryProvider.overrideWithValue(query),
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

  group('HistoryPaginationController 异步窗口契约', () {
    test('初次查询未完成时进入 loading 且没有伪造空态提交', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);

      final s = c.read(historyPaginationProvider);
      expect(s.isLoading, isTrue, reason: '查询在途时必须保持 loading');
      expect(s.isInitialized, isFalse, reason: '不得在结果到达前伪造提交');
      expect(s.conversations, isEmpty);
      expect(query.pendingCount, 1);

      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      expect(await outcome, HistoryWindowLoadOutcome.committed);
    });

    test('已初始化窗口重载期间保留旧列表并显示 busy', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final reload = c.read(historyPaginationProvider.notifier).setKeyword('x');

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((e) => e.id), ['a'], reason: '旧列表保留');
      expect(s.isLoading, isTrue);

      query.completeSuccess(1, items: [], totalItems: 0);
      expect(await reload, HistoryWindowLoadOutcome.committed);
    });

    test('活动请求期间连续提交三个目标时只执行首个和最后一个', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcomeA = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      final outcomeB = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('b');
      final outcomeC = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('c');

      // B 被 C 替换：公开 Future 立即以 ignored 结算，不进入查询。
      expect(await outcomeB, HistoryWindowLoadOutcome.ignored);
      expect(query.requests, hasLength(1), reason: '只有 A 已进入查询');

      // A 完成：已被超越，结果不提交。
      query.completeSuccess(0, items: [summary('a')], totalItems: 1);
      expect(await outcomeA, HistoryWindowLoadOutcome.ignored);
      expect(c.read(historyPaginationProvider).isInitialized, isFalse);

      expect(query.requests, hasLength(2), reason: 'A 结束后 C 立即派发');
      expect(query.requests.last.keyword, 'c');
      expect(query.requests.last.requestedPage, 1);

      query.completeSuccess(1, items: [summary('c1')], totalItems: 1);
      expect(await outcomeC, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).keyword, 'c');
    });

    test('旧成功完成时不覆盖新的 pending 目标', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcomeA = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('旧目标');
      final outcomeC = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('新目标');

      query.completeSuccess(1, items: [summary('stale')], totalItems: 5);
      expect(await outcomeA, HistoryWindowLoadOutcome.ignored);
      expect(
        c.read(historyPaginationProvider).conversations.map((e) => e.id),
        ['a'],
        reason: '旧成功不得写入 state',
      );

      query.completeSuccess(2, items: [summary('c1')], totalItems: 7);
      expect(await outcomeC, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).keyword, '新目标');
      expect(c.read(historyPaginationProvider).totalItems, 7);
    });

    test('旧失败完成时不覆盖新的 pending 目标', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcomeA = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('旧目标');
      final outcomeC = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('新目标');

      query.completeFailure(1);
      expect(await outcomeA, HistoryWindowLoadOutcome.ignored);
      expect(
        c.read(historyPaginationProvider).errorMessage,
        isNull,
        reason: '旧失败不得写入错误态',
      );

      query.completeSuccess(2, items: [summary('c1')], totalItems: 7);
      expect(await outcomeC, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).errorMessage, isNull);
    });

    test('最新失败保留已提交窗口并落 inline 错误状态', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('不存在的关键词');

      query.completeFailure(1);
      expect(await outcome, HistoryWindowLoadOutcome.failed);

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((e) => e.id), ['a'], reason: 'stale 内容保留');
      expect(s.errorMessage, historyLoadErrorMessage);
      expect(s.isInitialized, isTrue);
      expect(s.isLoading, isFalse);
      expect(s.keyword, '', reason: '失败目标的 keyword 不写入 committed 状态');
    });

    test('搜索请求未完成时清空关键词仍会提交空关键词目标', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcomeSearch = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('在途关键词');
      final outcomeClear = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('');

      query.completeSuccess(1, items: [summary('命中')], totalItems: 1);
      expect(await outcomeSearch, HistoryWindowLoadOutcome.ignored);

      // 清空目标必须真正进入查询：committed keyword 为空不代表没有在途目标。
      expect(query.requests.last.keyword, '');
      query.completeSuccess(2, items: [summary('a')], totalItems: 10);
      expect(await outcomeClear, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).conversations.map((e) => e.id), [
        'a',
      ]);
    });

    test('失败后的 retry 重新提交失败目标且可连续重试', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final failed = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('深链关键词');
      query.completeFailure(1);
      expect(await failed, HistoryWindowLoadOutcome.failed);

      final firstRetry = c.read(historyPaginationProvider.notifier).retry();
      expect(
        query.requests.last,
        HistoryPageRequest(keyword: '深链关键词', requestedPage: 1, pageSize: 20),
        reason: 'retry 必须重新提交失败目标',
      );
      query.completeFailure(2);
      expect(await firstRetry, HistoryWindowLoadOutcome.failed);

      // 失败目标不能因「已请求过」被缓存跳过。
      final secondRetry = c.read(historyPaginationProvider.notifier).retry();
      expect(query.requests.last.keyword, '深链关键词');
      query.completeSuccess(3, items: [summary('命中')], totalItems: 1);
      expect(await secondRetry, HistoryWindowLoadOutcome.committed);

      final s = c.read(historyPaginationProvider);
      expect(s.errorMessage, isNull);
      expect(s.keyword, '深链关键词');
    });

    test('dispose 后活动结果迟到不会写 state 且公开 Future 返回 ignored', () async {
      final query = ControllableHistoryPageQuery();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          historyPageQueryProvider.overrideWithValue(query),
        ],
      );
      final states = <HistoryPaginationState>[];
      c.listen(
        historyPaginationProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      expect(query.pendingCount, 1);
      final stateCountBeforeDispose = states.length;

      c.dispose();
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);

      expect(await outcome, HistoryWindowLoadOutcome.ignored);
      expect(
        states,
        hasLength(stateCountBeforeDispose),
        reason: '迟到结果不得写 state',
      );
    });

    test('搜索态 rename 强制刷新且不会被旧查询复活', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      // 在途搜索旧查询完成后不能把 rename 前的匹配集合写回。
      final outcomeSearch = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('旧');
      final outcomeRename = c
          .read(historyPaginationProvider.notifier)
          .afterRename('a', '新名字');

      query.completeSuccess(1, items: [summary('旧结果')], totalItems: 9);
      expect(await outcomeSearch, HistoryWindowLoadOutcome.ignored);

      expect(query.requests.last.keyword, '旧');
      query.completeSuccess(
        2,
        items: [summary('a'), summary('b')],
        totalItems: 2,
      );
      expect(await outcomeRename, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).conversations.map((e) => e.id), [
        'a',
        'b',
      ]);
      expect(c.read(historyPaginationProvider).totalItems, 2);
    });

    test('搜索态 delete 强制刷新且不会被删除前在途查询复活', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      // 删除触发按最新目标重查，删除前在途的旧查询结果不能写回。
      final outcomeSearch = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('旧');
      final outcomeDelete = c
          .read(historyPaginationProvider.notifier)
          .afterDelete({'a'});

      query.completeSuccess(1, items: [summary('旧结果')], totalItems: 9);
      expect(await outcomeSearch, HistoryWindowLoadOutcome.ignored);

      expect(query.requests.last.keyword, '旧');
      query.completeSuccess(2, items: [summary('b')], totalItems: 1);
      expect(await outcomeDelete, HistoryWindowLoadOutcome.committed);
      expect(c.read(historyPaginationProvider).conversations.map((e) => e.id), [
        'b',
      ]);
      expect(c.read(historyPaginationProvider).totalItems, 1);
    });

    test('查询在途时 goToPage 返回 ignored 且不发送新请求', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 40);
      await initial;

      final outcomeNext = c
          .read(historyPaginationProvider.notifier)
          .goToPage(2);
      final requestsDuringBusy = query.requests.length;

      final outcomeSkip = c
          .read(historyPaginationProvider.notifier)
          .goToPage(3);
      expect(await outcomeSkip, HistoryWindowLoadOutcome.ignored);
      expect(query.requests, hasLength(requestsDuringBusy));

      query.completeSuccess(1, items: [summary('b')], totalItems: 40);
      expect(await outcomeNext, HistoryWindowLoadOutcome.committed);
    });

    test('setPageSize 查询失败时可见窗口保持旧值', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .setPageSize(10);
      query.completeFailure(1);
      expect(await outcome, HistoryWindowLoadOutcome.failed);

      final s = c.read(historyPaginationProvider);
      expect(s.pageSize, 20, reason: '失败目标的容量不写入 committed 状态');
      expect(s.currentPage, 1);
      expect(s.errorMessage, isNotNull);
    });
  });

  group('HistoryPaginationController', () {
    test('loadRoute 默认加载第 1 页并写入 count 与 totalItems', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, hasLength(1));
      expect(s.totalItems, 10);
      expect(s.totalPages, 1);
      expect(s.currentPage, 1);
      expect(query.requests, hasLength(1));
    });

    test('loadRoute 空串关键词下 hasAnyConversations 跟随 totalItems', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: const [], totalItems: 0);
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.hasAnyConversations, isFalse);
      expect(s.totalItems, 0);
      expect(s.totalPages, 0);
    });

    test('loadRoute 带关键词时 hasAnyConversations 恒为 true', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: 'foo');
      query.completeSuccess(0, items: const [], totalItems: 0);
      await outcome;

      expect(c.read(historyPaginationProvider).hasAnyConversations, isTrue);
    });

    test('goToPage 跳转到目标页', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      final outcome = c.read(historyPaginationProvider.notifier).goToPage(3);
      expect(
        query.requests.last,
        HistoryPageRequest(keyword: '', requestedPage: 3, pageSize: 20),
      );
      query.completeSuccess(
        1,
        items: [summary('b'), summary('c')],
        totalItems: 50,
        committedPage: 3,
      );
      await outcome;

      expect(c.read(historyPaginationProvider).currentPage, 3);
    });

    test('goToPage 夹取越界页码（<1 视为 1，>totalPages 视为 totalPages）', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      var outcome = c.read(historyPaginationProvider.notifier).goToPage(99);
      query.completeSuccess(
        1,
        items: [summary('c')],
        totalItems: 50,
        committedPage: 3,
      );
      await outcome;
      expect(c.read(historyPaginationProvider).currentPage, 3); // ceil(50/20)

      outcome = c.read(historyPaginationProvider.notifier).goToPage(0);
      query.completeSuccess(2, items: [summary('a')], totalItems: 50);
      await outcome;
      expect(c.read(historyPaginationProvider).currentPage, 1);

      // 已处于第 1 页时 <1 的页码夹取回 1，与当前页相同直接 no-op。
      outcome = c.read(historyPaginationProvider.notifier).goToPage(-5);
      expect(await outcome, HistoryWindowLoadOutcome.ignored);
      expect(c.read(historyPaginationProvider).currentPage, 1);
    });

    test('goToPage 同一页直接返回', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;
      final requestsBefore = query.requests.length;

      final outcome = c.read(historyPaginationProvider.notifier).goToPage(1);

      expect(await outcome, HistoryWindowLoadOutcome.ignored);
      expect(query.requests, hasLength(requestsBefore));
    });

    test('setPageSize 重置到第 1 页并更新 totalPages', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      var outcome = c.read(historyPaginationProvider.notifier).goToPage(3);
      query.completeSuccess(
        1,
        items: [summary('c')],
        totalItems: 50,
        committedPage: 3,
      );
      await outcome;
      expect(c.read(historyPaginationProvider).currentPage, 3);
      final requestsBefore = query.requests.length;

      outcome = c.read(historyPaginationProvider.notifier).setPageSize(10);
      expect(query.requests, hasLength(requestsBefore + 1));
      expect(query.requests.last.requestedPage, 1);
      query.completeSuccess(
        2,
        items: [summary('b')],
        totalItems: 50,
        committedPage: 1,
      );
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.pageSize, 10);
      expect(s.currentPage, 1);
      expect(s.totalPages, 5); // ceil(50/10)
    });

    test('setPageSize 非法值不生效', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;
      final sizeBefore = c.read(historyPaginationProvider).pageSize;
      final requestsBefore = query.requests.length;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .setPageSize(999);

      expect(await outcome, HistoryWindowLoadOutcome.ignored);
      expect(c.read(historyPaginationProvider).pageSize, sizeBefore);
      expect(query.requests, hasLength(requestsBefore));
    });

    test('setKeyword 重置到第 1 页并刷新 count', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 30);
      await initial;

      var outcome = c.read(historyPaginationProvider.notifier).goToPage(2);
      query.completeSuccess(
        1,
        items: [summary('b')],
        totalItems: 30,
        committedPage: 2,
      );
      await outcome;
      expect(c.read(historyPaginationProvider).currentPage, 2);

      outcome = c.read(historyPaginationProvider.notifier).setKeyword('新关键词');
      expect(query.requests.last.keyword, '新关键词');
      expect(query.requests.last.requestedPage, 1);
      query.completeSuccess(
        2,
        items: [summary('b')],
        totalItems: 30,
        committedPage: 1,
      );
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.keyword, '新关键词');
      expect(s.currentPage, 1);
    });

    test('setKeyword 空串旧值下幂等', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;
      final requestsBefore = query.requests.length;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .setKeyword('   '); // trim 后为 ''

      expect(await outcome, HistoryWindowLoadOutcome.ignored);
      expect(query.requests, hasLength(requestsBefore));
    });

    test('afterRename 只更新当前页匹配项', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(
        0,
        items: [summary('a'), summary('b')],
        totalItems: 50,
      );
      await initial;
      final requestsBefore = query.requests.length;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .afterRename('a', '新名字');
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.firstWhere((e) => e.id == 'a').title, '新名字');
      expect(s.conversations.firstWhere((e) => e.id == 'b').title, '对话 b');
      expect(query.requests, hasLength(requestsBefore), reason: '非搜索态不重查');
    });

    test('afterDelete 按数据库真实结果补齐当前页窗口', () async {
      final all = List.generate(40, (i) => summary('item$i'));
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: all.sublist(0, 20), totalItems: 40);
      await initial;
      final requestsBefore = query.requests.length;

      // 40 条、每页 20：删除第 1 页首条后，重拉的第 1 页应仍为 20 条
      // （原第 2 页首项补入），下一页从原第 22 条开始不漏项。
      var outcome = c.read(historyPaginationProvider.notifier).afterDelete({
        'item0',
      });
      expect(query.requests, hasLength(requestsBefore + 1));
      expect(query.requests.last.requestedPage, 1);
      query.completeSuccess(
        1,
        items: [...all.sublist(1, 20), all[20]],
        totalItems: 39,
        committedPage: 1,
      );
      await outcome;

      var s = c.read(historyPaginationProvider);
      expect(s.totalItems, 39);
      expect(s.currentPage, 1);
      expect(s.conversations, hasLength(20));
      expect(s.conversations.last.id, 'item20');
      expect(s.errorMessage, isNull);

      // 下一页不漏项：从第 21 条开始。
      outcome = c.read(historyPaginationProvider.notifier).goToPage(2);
      expect(query.requests.last.requestedPage, 2);
      query.completeSuccess(
        2,
        items: all.sublist(21, 40),
        totalItems: 39,
        committedPage: 2,
      );
      await outcome;
      s = c.read(historyPaginationProvider);
      expect(
        s.conversations.map((e) => e.id),
        all.sublist(21, 40).map((e) => e.id),
      );
      expect(s.hasNext, isFalse);
    });

    test('搜索态 rename 使条目退出匹配时重拉并修正总数', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: '旧');
      query.completeSuccess(
        0,
        items: [summary('a'), summary('b')],
        totalItems: 2,
      );
      await initial;
      final requestsBefore = query.requests.length;

      // b 改名后不再命中。
      final outcome = c
          .read(historyPaginationProvider.notifier)
          .afterRename('b', '新名字');
      expect(query.requests, hasLength(requestsBefore + 1));
      expect(query.requests.last.keyword, '旧');
      query.completeSuccess(1, items: [summary('a')], totalItems: 1);
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((e) => e.id), ['a']);
      expect(s.totalItems, 1);
      expect(s.currentPage, 1);
    });

    test('搜索态 rename 使条目进入匹配时同样按查询结果呈现', () async {
      final renamed = summary('b').copyWith(title: '新名字');
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, keyword: '新');
      query.completeSuccess(0, items: [summary('a')], totalItems: 1);
      await initial;
      final requestsBefore = query.requests.length;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .afterRename('b', '新名字');
      expect(query.requests, hasLength(requestsBefore + 1));
      query.completeSuccess(1, items: [summary('a'), renamed], totalItems: 2);
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((e) => e.id), ['a', 'b']);
      expect(s.totalItems, 2);
    });

    test('afterDelete 全部删尽会清空并进入空库状态', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 1);
      await initial;

      final outcome = c.read(historyPaginationProvider.notifier).afterDelete({
        'a',
      });
      query.completeSuccess(1, items: const [], totalItems: 0);
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.conversations, isEmpty);
      expect(s.totalItems, 0);
      expect(s.hasAnyConversations, isFalse);
    });

    test('hasPrevious / hasNext 派生正确', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 60);
      await initial;

      expect(c.read(historyPaginationProvider).hasPrevious, isFalse);
      expect(c.read(historyPaginationProvider).hasNext, isTrue);

      final outcome = c.read(historyPaginationProvider.notifier).goToPage(3);
      query.completeSuccess(
        1,
        items: [summary('c')],
        totalItems: 60,
        committedPage: 3,
      );
      await outcome;
      expect(c.read(historyPaginationProvider).hasPrevious, isTrue);
      expect(c.read(historyPaginationProvider).hasNext, isFalse);
    });

    test('loadRoute 使用 route 页码、容量与关键词查询', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 2, pageSize: 10, keyword: '关键词');
      expect(
        query.requests.last,
        HistoryPageRequest(keyword: '关键词', requestedPage: 2, pageSize: 10),
      );
      query.completeSuccess(
        1,
        items: [summary('b')],
        totalItems: 50,
        committedPage: 2,
      );
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 2);
      expect(s.pageSize, 10);
      expect(s.keyword, '关键词');
      expect(s.totalItems, 50);
      expect(s.isInitialized, isTrue);
      expect(s.errorMessage, isNull);
    });

    test('loadRoute 关键词先 trim 再生效', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(keyword: '  空格  ');
      expect(query.requests.last.keyword, '空格');
      query.completeSuccess(1, items: [summary('b')], totalItems: 10);
      await outcome;

      expect(c.read(historyPaginationProvider).keyword, '空格');
    });

    test('loadRoute 非法容量回退持久化偏好', () async {
      preferences.setInt('app.feature.history.page_size', 10);
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1, pageSize: 999);
      expect(query.requests.last.pageSize, 10);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await outcome;

      expect(c.read(historyPaginationProvider).pageSize, 10);
    });

    test('loadRoute 页码越界夹取到查询后的真实末页', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      // 数据变化后真实末页为 3，越界请求夹取到第 3 页。
      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 99);
      query.completeSuccess(
        1,
        items: [summary('b')],
        totalItems: 50,
        committedPage: 3,
      );
      await outcome;

      expect(c.read(historyPaginationProvider).currentPage, 3);
    });

    test('loadRoute 总数为 0 时页码归一为 1', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 5);
      query.completeSuccess(
        1,
        items: const [],
        totalItems: 0,
        committedPage: 1,
      );
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.currentPage, 1);
      expect(s.totalItems, 0);
      expect(s.conversations, isEmpty);
    });

    test('查询失败时保留旧窗口内容并进入错误态', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 10);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 2);
      query.completeFailure(1);
      expect(await outcome, HistoryWindowLoadOutcome.failed);

      final s = c.read(historyPaginationProvider);
      expect(s.conversations.map((e) => e.id), ['a'], reason: '旧内容保留');
      expect(s.errorMessage, isNotNull);
      expect(s.isInitialized, isTrue);
      expect(s.currentPage, 1);
    });

    test('错误后重试成功清除错误并载入目标窗口', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      final failed = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 2);
      query.completeFailure(1);
      await failed;
      expect(c.read(historyPaginationProvider).errorMessage, isNotNull);

      final outcome = c.read(historyPaginationProvider.notifier).retry();
      expect(query.requests.last.requestedPage, 2);
      query.completeSuccess(
        2,
        items: [summary('b')],
        totalItems: 50,
        committedPage: 2,
      );
      await outcome;

      final s = c.read(historyPaginationProvider);
      expect(s.errorMessage, isNull);
      expect(s.currentPage, 2);
      expect(s.conversations.map((e) => e.id), ['b']);
    });

    test('setPageSize 将所选容量回写持久化偏好', () async {
      final query = ControllableHistoryPageQuery();
      final c = createContainer(query);
      final initial = c
          .read(historyPaginationProvider.notifier)
          .loadRoute(page: 1);
      query.completeSuccess(0, items: [summary('a')], totalItems: 50);
      await initial;

      final outcome = c
          .read(historyPaginationProvider.notifier)
          .setPageSize(10);
      query.completeSuccess(
        1,
        items: [summary('a')],
        totalItems: 50,
        committedPage: 1,
      );
      await outcome;

      expect(preferences.getInt('app.feature.history.page_size'), 10);
    });
  });
}
