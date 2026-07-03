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
  late ProviderContainer container;

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

  group('HistoryPaginationController', () {
    test('loadInitial 写入首份数据与 hasMore', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: [
              ChatConversationSummary(
                id: 'a',
                updatedAt: DateTime(2026, 6, 1),
              ),
            ],
            hasMore: true,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();

      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(1));
      expect(state.hasMore, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.keyword, '');
      expect(repo.callCount, 1);
      expect(repo.calls[0].limit, 50);
      expect(repo.calls[0].offset, 0);
    });

    test('loadMore 追加数据并更新 hasMore', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: List.generate(
              50,
              (i) => ChatConversationSummary(
                id: 'c$i',
                updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: true,
          ),
          (
            summaries: List.generate(
              20,
              (i) => ChatConversationSummary(
                id: 'c${50 + i}',
                updatedAt: DateTime(2026, 5, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      container.read(historyPaginationProvider.notifier).loadMore();

      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(70));
      expect(state.hasMore, isFalse);
      expect(state.isLoading, isFalse);
      expect(repo.callCount, 2);
      // 第二次调用是 loadMore：limit=30, offset=50。
      expect(repo.calls[1].limit, 30);
      expect(repo.calls[1].offset, 50);
    });

    test('isLoading 守卫阻止并发 loadMore', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: List.generate(
              50,
              (i) => ChatConversationSummary(
                id: 'c$i',
                updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: true,
          ),
          (
            summaries: List.generate(
              30,
              (i) => ChatConversationSummary(
                id: 'c${50 + i}',
                updatedAt: DateTime(2026, 5, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      // 连续调用两次 loadMore：第二次应被 isLoading 守卫拦截。
      container.read(historyPaginationProvider.notifier).loadMore();
      container.read(historyPaginationProvider.notifier).loadMore();

      // 仅触发一次 loadMore（第二次被 isLoading 守卫拦截）。
      expect(repo.callCount, 2);
      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(80));
      expect(state.hasMore, isFalse);
    });

    test('hasMore=false 后 loadMore 直接返回', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: List.generate(
              30,
              (i) => ChatConversationSummary(
                id: 'c$i',
                updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      container.read(historyPaginationProvider.notifier).loadMore();

      // loadMore 被 hasMore=false 守卫拦截，未触发第二次调用。
      expect(repo.callCount, 1);
      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(30));
      expect(state.hasMore, isFalse);
    });

    test('setKeyword 重置分页并应用新关键词', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: List.generate(
              50,
              (i) => ChatConversationSummary(
                id: 'c$i',
                updatedAt: DateTime(2026, 6, 1).add(Duration(minutes: i)),
              ),
            ),
            hasMore: true,
          ),
          (
            summaries: [
              ChatConversationSummary(
                id: 'match-1',
                title: '匹配项',
                updatedAt: DateTime(2026, 5, 1),
              ),
            ],
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      container.read(historyPaginationProvider.notifier).setKeyword('匹配');

      final state = container.read(historyPaginationProvider);
      expect(state.keyword, '匹配');
      expect(state.conversations, hasLength(1));
      expect(state.hasMore, isFalse);
      // 第二次调用带有关键词。
      expect(repo.calls[1].keyword, '匹配');
      expect(repo.calls[1].limit, 50);
      expect(repo.calls[1].offset, 0);
    });

    test('afterRename 在本地更新标题', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: [
              ChatConversationSummary(
                id: 'c1',
                title: '旧标题',
                updatedAt: DateTime(2026, 6, 1),
              ),
            ],
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      container.read(historyPaginationProvider.notifier).afterRename(
        'c1',
        '新标题',
      );

      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, '新标题');
    });

    test('afterDelete 在本地移除已删除项', () {
      final repo = FakeHistoryRepository(
        pages: [
          (
            summaries: [
              ChatConversationSummary(
                id: 'c1',
                updatedAt: DateTime(2026, 6, 1),
              ),
              ChatConversationSummary(
                id: 'c2',
                updatedAt: DateTime(2026, 6, 2),
              ),
            ],
            hasMore: false,
          ),
        ],
      );
      container = createContainer(repo);

      container.read(historyPaginationProvider.notifier).loadInitial();
      container
          .read(historyPaginationProvider.notifier)
          .afterDelete({'c1'});

      final state = container.read(historyPaginationProvider);
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.id, 'c2');
    });
  });
}
