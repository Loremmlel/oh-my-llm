import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
