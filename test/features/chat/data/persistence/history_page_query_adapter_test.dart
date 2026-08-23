import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_page_sizes.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/data/persistence/history_page_query_adapter.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_page_query_test');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // 句柄释放验证由专门用例负责；此处容忍偶发清理失败即可。
    }
  });

  String databasePath(String name) =>
      '${tempDir.path}${Platform.pathSeparator}$name.sqlite';

  ChatConversation conversation({
    required String id,
    required String title,
    required String userContent,
    required DateTime updatedAt,
    String assistantContent = '助手回复内容',
  }) {
    final userMessageId = '$id-user';
    final assistantMessageId = '$id-assistant';
    return ChatConversation(
      id: id,
      title: title,
      messageNodes: [
        TestFixtures.userMessage(
          id: userMessageId,
          content: userContent,
          createdAt: updatedAt,
          parentId: rootConversationParentId,
        ),
        TestFixtures.assistantMessage(
          id: assistantMessageId,
          content: assistantContent,
          createdAt: updatedAt.add(const Duration(seconds: 1)),
          parentId: userMessageId,
        ),
      ],
      selectedChildByParentId: {
        rootConversationParentId: userMessageId,
        userMessageId: assistantMessageId,
      },
      createdAt: updatedAt,
      updatedAt: updatedAt.add(const Duration(seconds: 1)),
    );
  }

  /// 直接 repository 的 count → 夹取 → page 结果，作为 adapter 等价性基准。
  HistoryPageResult directWindow(
    AppDatabase database, {
    required String keyword,
    required int requestedPage,
    required int pageSize,
  }) {
    final repository = SqliteChatConversationRepository(database);
    final totalItems = repository.countHistorySummaries(keyword: keyword);
    final totalPages = totalPagesForItems(totalItems, pageSize);
    final committedPage = clampPageToValidRange(requestedPage, totalPages);
    return HistoryPageResult(
      items: repository.loadHistorySummaries(
        keyword: keyword,
        limit: pageSize,
        offset: (committedPage - 1) * pageSize,
      ),
      totalItems: totalItems,
      committedPage: committedPage,
    );
  }

  group('SqliteHistoryPageQueryAdapter 文件库 worker', () {
    test('能读取主连接已提交的数据', () async {
      final database = AppDatabase.forPath(databasePath('committed'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      await SqliteChatConversationRepository(database).saveConversations([
        conversation(
          id: 'c1',
          title: '已提交会话',
          userContent: '主连接写入的内容',
          updatedAt: DateTime(2026, 6, 1, 10),
        ),
      ]);

      final result = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );

      expect(result.items.map((e) => e.id), ['c1']);
      expect(result.items.single.title, '已提交会话');
      expect(result.totalItems, 1);
      expect(result.committedPage, 1);
    });

    test('结果与直接 repository 的 count 夹取 page 完全等价', () async {
      final database = AppDatabase.forPath(databasePath('equivalence'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      final base = DateTime(2026, 6, 1, 12);
      await SqliteChatConversationRepository(database).saveConversations([
        for (var i = 0; i < 45; i++)
          conversation(
            id: 'item$i',
            title: '批量会话 $i',
            userContent: '批量用户消息 $i',
            updatedAt: base.subtract(Duration(minutes: i)),
          ),
      ]);

      // 覆盖空结果、越界页（上下双侧）、排序与 10/20/50 容量。
      const scenarios = <(String keyword, int requestedPage, int pageSize)>[
        ('', 1, 10),
        ('', 2, 10),
        ('', 99, 10),
        ('', 0, 10),
        ('', 3, 20),
        ('', 3, 50),
        ('不存在的关键词', 1, 20),
        ('批量会话 4', 1, 20),
        ('批量用户消息 12', 1, 20),
      ];
      for (final (keyword, requestedPage, pageSize) in scenarios) {
        final viaAdapter = await adapter.load(
          HistoryPageRequest(
            keyword: keyword,
            requestedPage: requestedPage,
            pageSize: pageSize,
          ),
        );
        final expected = directWindow(
          database,
          keyword: keyword,
          requestedPage: requestedPage,
          pageSize: pageSize,
        );
        expect(
          viaAdapter.items,
          expected.items,
          reason: 'keyword=$keyword page=$requestedPage size=$pageSize 的页数据',
        );
        expect(
          viaAdapter.totalItems,
          expected.totalItems,
          reason: 'keyword=$keyword 的总数',
        );
        expect(
          viaAdapter.committedPage,
          expected.committedPage,
          reason: 'page=$requestedPage size=$pageSize 的夹取结果',
        );
      }
    });

    test('关键词保持标题和用户消息匹配且按字面转义百分号与下划线', () async {
      final database = AppDatabase.forPath(databasePath('keyword'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      final updated = DateTime(2026, 6, 2, 9);
      await SqliteChatConversationRepository(database).saveConversations([
        conversation(
          id: 'percent',
          title: '进度 100% 完成',
          userContent: '常规内容',
          updatedAt: updated,
        ),
        conversation(
          id: 'underscore',
          title: '下划线标题',
          userContent: '包含 foo_bar 的用户消息',
          updatedAt: updated.subtract(const Duration(minutes: 1)),
        ),
        conversation(
          id: 'wildcard-bait',
          title: '通配诱饵标题',
          userContent: '包含 fooXbar 的用户消息',
          updatedAt: updated.subtract(const Duration(minutes: 2)),
        ),
        conversation(
          id: 'assistant-only',
          title: '助手内容标题',
          userContent: '常规输入',
          assistantContent: '只出现在助手的机密词',
          updatedAt: updated.subtract(const Duration(minutes: 3)),
        ),
        conversation(
          id: 'case-title',
          title: 'Flutter ROADMAP',
          userContent: '常规输入 2',
          updatedAt: updated.subtract(const Duration(minutes: 4)),
        ),
      ]);

      Future<List<String>> idsOf(String keyword) async {
        final result = await adapter.load(
          HistoryPageRequest(keyword: keyword, requestedPage: 1, pageSize: 20),
        );
        return result.items.map((e) => e.id).toList();
      }

      expect(await idsOf('100%'), ['percent'], reason: '% 按字面匹配');
      expect(await idsOf('foo_bar'), ['underscore'], reason: '_ 按字面匹配');
      expect(await idsOf('fooXbar'), ['wildcard-bait'], reason: '字面 _ 不充当单字通配');
      expect(await idsOf('机密词'), isEmpty, reason: 'assistant 回复不参与匹配');
      expect(await idsOf('roadmap'), ['case-title'], reason: '标题大小写不敏感');
      expect(await idsOf('下划线标题'), ['underscore'], reason: '标题匹配');
    });

    test('主连接提交新增或删除后下一次 worker 查询可见', () async {
      final database = AppDatabase.forPath(databasePath('visibility'));
      final repository = SqliteChatConversationRepository(database);
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      final base = DateTime(2026, 6, 3, 8);
      await repository.saveConversations([
        conversation(
          id: 'old',
          title: '旧会话',
          userContent: '旧内容',
          updatedAt: base,
        ),
      ]);

      var result = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );
      expect(result.items.map((e) => e.id), ['old']);

      await repository.saveConversations([
        conversation(
          id: 'new',
          title: '新会话',
          userContent: '新内容',
          updatedAt: base.add(const Duration(hours: 1)),
        ),
      ]);
      result = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );
      expect(result.items.map((e) => e.id), ['new', 'old']);
      expect(result.totalItems, 2);

      await repository.deleteConversations(['old']);
      result = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );
      expect(result.items.map((e) => e.id), ['new']);
      expect(result.totalItems, 1);
    });

    test('缺表等 SQLite 失败映射为 HistoryPageQueryException', () async {
      final database = AppDatabase.forPath(databasePath('missing-table'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      await SqliteChatConversationRepository(database).saveConversations([
        conversation(
          id: 'c1',
          title: '种子',
          userContent: '内容',
          updatedAt: DateTime(2026, 6, 4, 7),
        ),
      ]);
      database.connection.execute('DROP TABLE messages;');

      await expectLater(
        adapter.load(
          HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
        ),
        throwsA(isA<HistoryPageQueryException>()),
      );
    });

    test('worker 启动失败时 load 立即失败且后续 load 不再重试', () async {
      final database = AppDatabase.forPath(databasePath('startup-failure'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(() async {
        await adapter.dispose();
        database.close();
      });
      // 主连接打开成功后把版本改成未来值：worker 以独立连接打开同一路径时
      // 被 schema 版本拒绝，产生确定性的 startup failure。
      database.connection.execute('PRAGMA user_version = 999;');

      await expectLater(
        adapter.load(
          HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
        ),
        throwsA(isA<HistoryPageQueryException>()),
      );
      await expectLater(
        adapter.load(
          HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
        ),
        throwsA(isA<HistoryPageQueryException>()),
      );
    });

    test('dispose 后 load 失败且第二次 dispose 正常完成', () async {
      final database = AppDatabase.forPath(databasePath('dispose'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(database.close);

      await adapter.dispose();

      await expectLater(
        adapter.load(
          HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
        ),
        throwsA(isA<HistoryPageQueryException>()),
      );
      await adapter.dispose();
    });

    test('启动未就绪时 dispose 使在途 load 立即失败而非悬挂', () async {
      final database = AppDatabase.forPath(databasePath('dispose-startup'));
      final adapter = SqliteHistoryPageQueryAdapter(database);
      addTearDown(database.close);

      final loadFuture = adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );
      // 观察必须先于 dispose 挂接：错误在 dispose 的同步前缀就落地，若
      // attach 晚于微任务传递，会以未处理异步错误污染测试。timeout 只是
      // 红灯兜底：契约要求 dispose 后 load 失败而非永久悬挂。
      final observed = expectLater(
        loadFuture.timeout(const Duration(seconds: 5)),
        throwsA(isA<HistoryPageQueryException>()),
      );
      await adapter.dispose();
      await observed;
    });

    test('dispose 完成后主连接可关闭且 sqlite 残留文件可删除', () async {
      final path = databasePath('handles');
      final database = AppDatabase.forPath(path);
      final repository = SqliteChatConversationRepository(database);
      final adapter = SqliteHistoryPageQueryAdapter(database);
      await repository.saveConversations([
        conversation(
          id: 'c1',
          title: '句柄验证',
          userContent: '内容',
          updatedAt: DateTime(2026, 6, 5, 6),
        ),
      ]);
      // 触发 worker spawn 并完成一次真实查询。
      final result = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
      );
      expect(result.totalItems, 1);

      await adapter.dispose();
      database.close();

      // Windows 上仍被 worker 句柄持有的文件删除会失败；删除成功即证明
      // worker 已释放数据库文件（含 wal/shm 若仍残留）。
      File(path).deleteSync();
      for (final suffix in ['-wal', '-shm']) {
        final file = File('$path$suffix');
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  });

  group('SqliteHistoryPageQueryAdapter 内存库', () {
    test('读取同一 AppDatabase 的种子数据并与直接查询语义等价', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = SqliteChatConversationRepository(database);
      final base = DateTime(2026, 6, 6, 5);
      await repository.saveConversations([
        for (var i = 0; i < 3; i++)
          conversation(
            id: 'mem$i',
            title: '内存会话 $i',
            userContent: '内存用户消息 $i',
            updatedAt: base.subtract(Duration(minutes: i)),
          ),
      ]);
      final adapter = SqliteHistoryPageQueryAdapter(database);

      final page1 = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 2),
      );
      expect(page1.items.map((e) => e.id), ['mem0', 'mem1']);
      expect(page1.totalItems, 3);
      expect(page1.committedPage, 1);

      final page2 = await adapter.load(
        HistoryPageRequest(keyword: '', requestedPage: 2, pageSize: 2),
      );
      expect(page2.items.map((e) => e.id), ['mem2']);
      expect(page2.committedPage, 2);

      final search = await adapter.load(
        HistoryPageRequest(keyword: '内存会话 2', requestedPage: 1, pageSize: 2),
      );
      expect(search.items.map((e) => e.id), ['mem2']);
      expect(search.totalItems, 1);

      await adapter.dispose();
    });

    test('dispose 后新 load 立即失败且不再走内存直查', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await SqliteChatConversationRepository(database).saveConversations([
        conversation(
          id: 'mem',
          title: '内存会话',
          userContent: '内容',
          updatedAt: DateTime(2026, 6, 7, 5),
        ),
      ]);
      final adapter = SqliteHistoryPageQueryAdapter(database);

      await adapter.dispose();

      // 种子数据可查证明失败来自 dispose 拦截，而不是数据为空等偶发错误。
      await expectLater(
        adapter.load(
          HistoryPageRequest(keyword: '', requestedPage: 1, pageSize: 20),
        ),
        throwsA(isA<HistoryPageQueryException>()),
      );
    });
  });
}
