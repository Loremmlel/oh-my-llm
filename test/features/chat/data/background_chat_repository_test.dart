import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  late String tempDbPath;
  late AppDatabase db;

  setUp(() {
    tempDbPath =
        '${Directory.systemTemp.path}/test_bg_repo_${DateTime.now().millisecondsSinceEpoch}.sqlite';
    db = AppDatabase.forPath(tempDbPath);
  });

  tearDown(() {
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
    test('saveConversation via Isolate writes and inner repo reads back',
        () async {
      final inner = SqliteChatConversationRepository(db);
      final bg = BackgroundChatConversationRepository(inner, tempDbPath);

      final conv = makeConv('isolate_test', 'Hello from Isolate');
      await bg.saveConversation(conv);

      // 等待 debounce（80 ms）+ Isolate 跨线程打开 DB 并写入
      await Future.delayed(const Duration(milliseconds: 200));

      final loaded = inner.loadConversation('isolate_test');
      expect(loaded, isNotNull);
      expect(loaded!.messages.length, 1);
      expect(loaded.messages.first.content, 'Hello from Isolate');
    });

    test(
        'Map merge: two different conversations within debounce window '
        'both persisted', () async {
      final inner = SqliteChatConversationRepository(db);
      final bg = BackgroundChatConversationRepository(inner, tempDbPath);

      final convA = makeConv('conv_a', 'Content A');
      final convB = makeConv('conv_b', 'Content B');

      // 在 80 ms 窗口内快速连续写入两条不同 ID 的会话
      await bg.saveConversation(convA);
      await bg.saveConversation(convB);

      await Future.delayed(const Duration(milliseconds: 200));

      final loadedA = inner.loadConversation('conv_a');
      final loadedB = inner.loadConversation('conv_b');
      expect(loadedA, isNotNull);
      expect(loadedB, isNotNull);
      expect(loadedA!.messages.first.content, 'Content A');
      expect(loadedB!.messages.first.content, 'Content B');
    });

    test(
        'Map merge: same conversation twice within debounce window, '
        'last write wins via Map overwrite', () async {
      final inner = SqliteChatConversationRepository(db);
      final bg = BackgroundChatConversationRepository(inner, tempDbPath);

      final convOrig = makeConv('same_conv', 'Original content');
      final convModified = makeConv('same_conv', 'Modified content');

      // 同一 ID 的两次写入，Map 应覆盖前者
      await bg.saveConversation(convOrig);
      await bg.saveConversation(convModified);

      await Future.delayed(const Duration(milliseconds: 200));

      final loaded = inner.loadConversation('same_conv');
      expect(loaded, isNotNull);
      expect(
        loaded!.messages.first.content,
        'Modified content',
        reason: 'Map merge 应以最后一次写入为准',
      );
    });

    test(
        'Pending write management: saveConversation before Isolate ready '
        'still persists data after Isolate initializes', () async {
      final inner = SqliteChatConversationRepository(db);
      final bg = BackgroundChatConversationRepository(inner, tempDbPath);

      // 构造后立即调用 saveConversation —— Isolate 大概率尚未就绪
      final conv = makeConv('pending_test', 'Pending write');
      await bg.saveConversation(conv);

      // 留出充足时间：Isolate 启动 → 接收 pending 数据 → 写入 DB
      await Future.delayed(const Duration(milliseconds: 300));

      final loaded = inner.loadConversation('pending_test');
      expect(loaded, isNotNull);
      expect(loaded!.messages.first.content, 'Pending write');
    });

    test(
        'deleteConversations clears pending writes for deleted conversation',
        () async {
      final inner = SqliteChatConversationRepository(db);
      final bg = BackgroundChatConversationRepository(inner, tempDbPath);

      final conv = makeConv('to_delete', 'Will be deleted');
      await bg.saveConversation(conv);

      // 在 debounce 触发前立即删除
      await bg.deleteConversations(['to_delete']);

      await Future.delayed(const Duration(milliseconds: 200));

      // 内层仓库已同步删除；debounce 触发时 pending write 应被清除，
      // 不会通过 Isolate 重新写入
      final loaded = inner.loadConversation('to_delete');
      expect(loaded, isNull);
    });

    test(':memory: database falls back to inner repo synchronously', () async {
      // 内存数据库不走 Isolate 管道，直接委托内层仓库写入
      final memDb = AppDatabase.inMemory();
      addTearDown(() => memDb.close());

      final inner = SqliteChatConversationRepository(memDb);
      final bg = BackgroundChatConversationRepository(inner, ':memory:');

      final conv = makeConv('mem_test', 'Memory fallback');
      await bg.saveConversation(conv);

      // 无 Isolate 延迟，内层仓库应立即持久化
      final loaded = inner.loadConversation('mem_test');
      expect(loaded, isNotNull);
      expect(loaded!.messages.first.content, 'Memory fallback');
    });
  });
}
