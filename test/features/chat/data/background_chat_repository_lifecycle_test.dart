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
    test('saveConversation Future 完成时数据必须立即可读（ACK 语义契约）', () async {
      final inner = SqliteChatConversationRepository(db);
      bg = BackgroundChatConversationRepository(inner, tempDbPath);

      final conv = makeConv('ack_contract', 'ACK contract');
      await bg.saveConversation(conv);
      // Future 完成 = worker 已 ACK = 数据已 COMMIT 落盘（修复后契约成立）
      final loaded = inner.loadConversation('ack_contract');
      expect(loaded, isNotNull);
      expect(loaded!.messages.first.content, 'ACK contract');

      await bg.close();
    });

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
        bg = BackgroundChatConversationRepository(inner, tempDbPath);

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
      'sequential saves across debounce windows each complete independently',
      () async {
        final inner = SqliteChatConversationRepository(db);
        bg = BackgroundChatConversationRepository(inner, tempDbPath);

        // 第一次 save：Future 完成即第一批已落盘并 ACK，debounce 窗口随之关闭。
        await bg.saveConversation(makeConv('seq_1', 'First'));

        // 各批次行数分别断言：第一批只含 seq_1。若第一批未落盘（早 ACK 回归——
        // Future 先于落盘完成），此刻磁盘上应为 0 行。
        var rows = inner.loadAll();
        expect(rows.length, 1);
        expect(rows.single.id, 'seq_1');

        // 直接发第二次保存并 await 其 Future：无需等待 debounce 窗口——第一批
        // ACK 已证明窗口关闭，第二批必然独立成批、独立 ACK。
        await bg.saveConversation(makeConv('seq_2', 'Second'));

        rows = inner.loadAll();
        expect(rows.length, 2);
        expect(rows.map((c) => c.id), containsAll(['seq_1', 'seq_2']));

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
