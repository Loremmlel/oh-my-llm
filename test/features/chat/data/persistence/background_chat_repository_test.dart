import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/persistence/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  late String tempDbPath;
  late AppDatabase db;
  // 顶层持有当前 test 的 bg，供 tearDown 兜底关闭（即便 test 抛异常也清理 Isolate）。
  // late 非 final：每个 test body 重新赋值；tearDown 用 try-catch 兜底未赋值场景。
  late BackgroundChatConversationRepository bg;

  setUp(() {
    tempDbPath =
        '${Directory.systemTemp.path}/test_bg_repo_${DateTime.now().millisecondsSinceEpoch}.sqlite';
    db = AppDatabase.forPath(tempDbPath);
  });

  tearDown(() async {
    // 兜底关闭 bg：即使 test 在 bg.close() 前抛异常，也确保 Isolate 被清理，
    // 避免残留进程锁住 native assets dll 导致后续 test 连锁阻塞。
    try {
      await bg.close();
    } catch (_) {}
    db.close();
    // 清理临时数据库文件及 WAL/SHM 附属文件；Isolate 可能仍持有连接，
    // 因此以 try/catch 静默处理删除失败。
    try {
      File(tempDbPath).deleteSync();
    } catch (_) {}
    try {
      File('$tempDbPath-wal').deleteSync();
    } catch (_) {}
    try {
      File('$tempDbPath-shm').deleteSync();
    } catch (_) {}
  });

  /// 创建一个带有一条用户消息的最小测试会话。
  ChatConversation makeConv(String id, String content) {
    final msg = ChatMessage(
      id: '${id}_msg',
      role: ChatMessageRole.user,
      content: content,
      createdAt: DateTime.now(),
      parentId: rootConversationParentId,
    );
    return ChatConversation(
      id: id,
      messageNodes: [msg],
      selectedChildByParentId: {rootConversationParentId: msg.id},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  group('BackgroundChatConversationRepository', () {
    test('Pending write management: saveConversation before Isolate ready '
        'still persists data after Isolate initializes', () async {
      final inner = SqliteChatConversationRepository(db);
      bg = BackgroundChatConversationRepository(inner, tempDbPath);

      // 构造后立即调用 saveConversation —— Isolate 大概率尚未就绪
      final conv = makeConv('pending_test', 'Pending write');
      await bg.saveConversation(conv);
      // saveConversation 在 ACK 后完成，pending write 已被 Isolate 消费

      final loaded = inner.loadConversation('pending_test');
      expect(loaded, isNotNull);
      expect(loaded!.messages.first.content, 'Pending write');

      await bg.close();
    });

    test(
      'deleteConversations clears pending writes for deleted conversation',
      () async {
        final inner = SqliteChatConversationRepository(db);
        bg = BackgroundChatConversationRepository(inner, tempDbPath);

        final conv = makeConv('to_delete', 'Will be deleted');
        final saveFuture = bg.saveConversation(conv);

        // 不等待 save ACK，在同一 debounce 窗口内立即删除。
        await bg.deleteConversations(['to_delete']);
        await bg.flush();
        await saveFuture;

        // 内层仓库已同步删除；debounce 触发时 pending write 应被清除，
        // 不会通过 Isolate 重新写入
        final loaded = inner.loadConversation('to_delete');
        expect(loaded, isNull);

        await bg.close();
      },
    );

    test(':memory: database falls back to inner repo synchronously', () async {
      // 内存数据库不走 Isolate 管道，直接委托内层仓库写入
      final memDb = AppDatabase.inMemory();
      addTearDown(() => memDb.close());

      final inner = SqliteChatConversationRepository(memDb);
      bg = BackgroundChatConversationRepository(inner, ':memory:');

      final conv = makeConv('mem_test', 'Memory fallback');
      await bg.saveConversation(conv);

      // 无 Isolate 延迟，内层仓库应立即持久化
      final loaded = inner.loadConversation('mem_test');
      expect(loaded, isNotNull);
      expect(loaded!.messages.first.content, 'Memory fallback');

      await bg.close();
    });
  });
}
