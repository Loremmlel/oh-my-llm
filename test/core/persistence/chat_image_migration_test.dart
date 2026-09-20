import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../helpers/chat/test_chat_images.dart';

void main() {
  test('合法 v22 数据库迁移保留旧消息并仅持久化图片引用', () async {
    final directory = await Directory.systemTemp.createTemp(
      'chat-image-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/chat.sqlite';
    final legacy = sqlite3.open(path);
    legacy.execute(
      File('test/helpers/fixtures/schema_v21.sql').readAsStringSync(),
    );
    legacy.execute(
      File('test/helpers/fixtures/schema_v22_from_v21.sql').readAsStringSync(),
    );
    legacy.execute(
      "INSERT INTO conversations (id, created_at, updated_at, reasoning_effort) VALUES ('legacy', '2026-01-01', '2026-01-01', 'medium');",
    );
    legacy.execute(
      "INSERT INTO messages (id, conversation_id, node_index, role, content, reasoning_content, created_at) VALUES ('old', 'legacy', 0, 'user', '旧正文', '独立推理', '2026-01-01');",
    );
    legacy.close();
    final migrated = AppDatabase.forPath(path);
    final repository = SqliteChatConversationRepository(migrated);
    final old = repository.loadConversation('legacy')!.messageNodes.single;
    expect(old.content, '旧正文');
    expect(old.reasoningContent, '独立推理');
    expect(old.images, isEmpty);
    expect(
      migrated.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
    );
    final now = DateTime(2026, 9, 20);
    final conversation = ChatConversation(
      id: 'image-chat',
      createdAt: now,
      updatedAt: now,
      messageNodes: [
        ChatMessage(
          id: 'image-message',
          role: ChatMessageRole.user,
          content: '',
          createdAt: now,
          images: [testChatImage],
        ),
      ],
    );
    await repository.saveConversation(conversation);
    final json =
        migrated.connection
                .select(
                  "SELECT images_json FROM messages WHERE id = 'image-message'",
                )
                .single['images_json']
            as String;
    expect(json, contains(testChatImage.id));
    expect(json, isNot(contains('base64')));
    migrated.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    final loaded = SqliteChatConversationRepository(reopened);
    expect(loaded.loadConversation('image-chat')!.messageNodes.single.images, [
      testChatImage,
    ]);
    expect(
      loaded
          .loadAll()
          .singleWhere((c) => c.id == 'image-chat')
          .messageNodes
          .single
          .images,
      [testChatImage],
    );
  });
}
