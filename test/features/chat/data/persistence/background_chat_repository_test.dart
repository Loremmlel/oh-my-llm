import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/persistence/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

ChatConversation _conversation(String id, String content) {
  final now = DateTime(2026, 10, 7);
  return ChatConversation(
    id: id,
    messageNodes: [
      ChatMessage(
        id: '$id-message',
        role: ChatMessageRole.user,
        content: content,
        createdAt: now,
        parentId: rootConversationParentId,
      ),
    ],
    selectedChildByParentId: {rootConversationParentId: '$id-message'},
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('文件库后台写入', () {
    late Directory directory;
    late AppDatabase database;
    late SqliteChatConversationRepository inner;
    late BackgroundChatConversationRepository background;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('chat-background-');
      final path = '${directory.path}/chat.sqlite';
      database = AppDatabase.forPath(path);
      inner = SqliteChatConversationRepository(database);
      background = BackgroundChatConversationRepository(inner, path);
    });
    tearDown(() async {
      // 失败用例也必须释放 worker，关闭失败应暴露出来，不能静默吞掉。
      try {
        await background.close();
      } finally {
        database.close();
        directory.deleteSync(recursive: true);
      }
    });

    test('启动后立即保存，首次和后续 ACK 完成时数据均已提交', () async {
      final first = _conversation('first', '首次写入');
      await background.saveConversation(first);
      expect(inner.loadAll(), [first]);

      final second = _conversation('second', '下一批写入');
      await background.saveConversation(second);
      expect(inner.loadAll(), unorderedEquals([first, second]));
    });

    test('删除尚未 ACK 的会话后刷新不会复活已删除数据', () async {
      final saved = background.saveConversation(
        _conversation('deleted', '待删除'),
      );
      await background.deleteConversations(['deleted']);
      await background.flush();
      await saved;
      expect(inner.loadConversation('deleted'), isNull);
    });

    test('刷新等待全部在途写入，同一会话的最新版本覆盖旧版本', () async {
      final first = _conversation('first', '旧内容');
      final latest = first.copyWith(
        messageNodes: [first.messageNodes.single.copyWith(content: '最新内容')],
      );
      final second = _conversation('second', '另一会话');
      final saves = [
        background.saveConversation(first),
        background.saveConversation(second),
        background.saveConversation(latest),
      ];

      await background.flush();
      // 先读取再等待各 save，才能检测 flush 提前返回的回归。
      expect(inner.loadAll(), unorderedEquals([latest, second]));
      await Future.wait(saves);
    });

    test('关闭先提交待写内容，重复关闭和关闭后刷新均安全', () async {
      final conversation = _conversation('closing', '关闭前的内容');
      final saved = background.saveConversation(conversation);
      await background.close();
      expect(inner.loadConversation(conversation.id), conversation);
      await saved;
      await background.close();
      await background.flush();
    });
  });

  test('内存库直接保存到同一内层仓库', () async {
    final database = AppDatabase.inMemory();
    final inner = SqliteChatConversationRepository(database);
    final background = BackgroundChatConversationRepository(inner, ':memory:');
    addTearDown(() async {
      await background.close();
      database.close();
    });
    final conversation = _conversation('memory', '内存内容');
    await background.saveConversation(conversation);
    expect(inner.loadConversation(conversation.id), conversation);
  });
}
