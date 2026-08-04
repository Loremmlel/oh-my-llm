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
  // 顶层持有当前 test 的 bg，供 tearDown 兜底关闭（即便 test 抛异常也清理 Isolate）。
  // late 非 final：每个 test body 重新赋值；tearDown 用 try-catch 兜底未赋值场景。
  late BackgroundChatConversationRepository bg;

  setUp(() {
    tempDbPath =
        '${Directory.systemTemp.path}/test_bg_lifecycle_${DateTime.now().millisecondsSinceEpoch}.sqlite';
    db = AppDatabase.forPath(tempDbPath);
  });

  tearDown(() async {
    // 兜底关闭 bg：即使 test 在 bg.close() 前抛异常，也确保 Isolate 被清理，
    // 避免残留进程锁住 native assets dll 导致后续 test 连锁阻塞。
    try {
      await bg.close();
    } catch (_) {}
    db.close();
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

  group('ACK/flush/close lifecycle', () {
    test(
      'saveConversation Future completes after ACK (data durably on disk)',
      () async {
        final inner = SqliteChatConversationRepository(db);
        final bg = BackgroundChatConversationRepository(inner, tempDbPath);

        final conv = makeConv('ack_test', 'ACK verify');
        // Future 完成即意味着 ACK 已收到，数据已落盘
        await bg.saveConversation(conv);

        final loaded = inner.loadConversation('ack_test');
        expect(loaded, isNotNull);
        expect(loaded!.messages.first.content, 'ACK verify');

        await bg.close();
      },
    );

    test('flush waits for all pending writes to land', () async {
      final inner = SqliteChatConversationRepository(db);
      bg = BackgroundChatConversationRepository(inner, tempDbPath);

      // 不 await save，fire-and-forget
      bg.saveConversation(makeConv('flush_a', 'Flush A'));
      bg.saveConversation(makeConv('flush_b', 'Flush B'));

      // flush 应等所有 pending writes 落盘
      await bg.flush();

      expect(inner.loadConversation('flush_a'), isNotNull);
      expect(inner.loadConversation('flush_b'), isNotNull);

      await bg.close();
    });

    test('close flushes pending writes and shuts down worker', () async {
      final inner = SqliteChatConversationRepository(db);
      bg = BackgroundChatConversationRepository(inner, tempDbPath);

      bg.saveConversation(makeConv('close_test', 'Before close'));

      // close 应先 flush 再退出 worker
      await bg.close();

      expect(inner.loadConversation('close_test'), isNotNull);
    });

    test(
      'debounce merge: multiple saves in same window share one ACK',
      () async {
        final inner = SqliteChatConversationRepository(db);
        final bg = BackgroundChatConversationRepository(inner, tempDbPath);

        // 快速连续三次 save，应在同一 debounce 窗口内合并
        final future1 = bg.saveConversation(makeConv('merge_a', 'A'));
        final future2 = bg.saveConversation(makeConv('merge_b', 'B'));
        final future3 = bg.saveConversation(makeConv('merge_c', 'C'));

        // 全部 await——它们共享同一个 batch Completer
        await Future.wait([future1, future2, future3]);

        expect(inner.loadConversation('merge_a'), isNotNull);
        expect(inner.loadConversation('merge_b'), isNotNull);
        expect(inner.loadConversation('merge_c'), isNotNull);

        await bg.close();
      },
    );

    test(
      ':memory: path does not spawn Isolate and flush/close are no-ops',
      () async {
        final memDb = AppDatabase.inMemory();
        addTearDown(() => memDb.close());

        final inner = SqliteChatConversationRepository(memDb);
        bg = BackgroundChatConversationRepository(inner, ':memory:');

        await bg.saveConversation(makeConv('mem_lifecycle', 'In memory'));
        await bg.flush();
        await bg.close();

        expect(inner.loadConversation('mem_lifecycle'), isNotNull);
      },
    );

    test(
      'sequential saves across debounce windows each complete independently',
      () async {
        final inner = SqliteChatConversationRepository(db);
        final bg = BackgroundChatConversationRepository(inner, tempDbPath);

        // 第一次 save
        await bg.saveConversation(makeConv('seq_1', 'First'));

        // 等 debounce 窗口过去再第二次 save
        await Future.delayed(const Duration(milliseconds: 100));
        await bg.saveConversation(makeConv('seq_2', 'Second'));

        expect(inner.loadConversation('seq_1'), isNotNull);
        expect(inner.loadConversation('seq_2'), isNotNull);

        await bg.close();
      },
    );

    test('flush after close is safe', () async {
      final inner = SqliteChatConversationRepository(db);
      bg = BackgroundChatConversationRepository(inner, tempDbPath);

      await bg.saveConversation(makeConv('safe_flush', 'Safe'));
      await bg.close();

      // flush after close 应不抛异常
      await bg.flush();
    });
  });
}
