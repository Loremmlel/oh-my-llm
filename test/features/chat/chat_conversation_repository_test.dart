import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  test('sqlite repository saves and restores branched conversations', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteChatConversationRepository(database);
    final conversation = ChatConversation(
      id: 'conversation-1',
      title: '分支会话',
      messages: [
        ChatMessage(
          id: 'user-1',
          role: ChatMessageRole.user,
          content: '当前用户分支',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 4, 27, 10),
          userMessageSegments: const [
            UserMessageSegment(
              text: '当前',
              kind: UserMessageSegmentKind.template,
            ),
            UserMessageSegment(text: '用户分支', kind: UserMessageSegmentKind.body),
          ],
        ),
        ChatMessage(
          id: 'assistant-2',
          role: ChatMessageRole.assistant,
          content: '当前助手分支',
          parentId: 'user-1',
          reasoningContent: '保留思考内容',
          appliedCheckpointTitle: '检查点 1',
          createdAt: DateTime(2026, 4, 27, 10, 2),
        ),
      ],
      messageNodes: [
        ChatMessage(
          id: 'user-1',
          role: ChatMessageRole.user,
          content: '当前用户分支',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 4, 27, 10),
          userMessageSegments: const [
            UserMessageSegment(
              text: '当前',
              kind: UserMessageSegmentKind.template,
            ),
            UserMessageSegment(text: '用户分支', kind: UserMessageSegmentKind.body),
          ],
        ),
        ChatMessage(
          id: 'assistant-1',
          role: ChatMessageRole.assistant,
          content: '旧助手分支',
          parentId: 'user-1',
          createdAt: DateTime(2026, 4, 27, 10, 1),
        ),
        ChatMessage(
          id: 'assistant-2',
          role: ChatMessageRole.assistant,
          content: '当前助手分支',
          parentId: 'user-1',
          reasoningContent: '保留思考内容',
          createdAt: DateTime(2026, 4, 27, 10, 2),
        ),
      ],
      excludedMessageIds: const ['assistant-2'],
      selectedChildByParentId: const {
        rootConversationParentId: 'user-1',
        'user-1': 'assistant-2',
      },
      createdAt: DateTime(2026, 4, 27, 10),
      updatedAt: DateTime(2026, 4, 27, 10, 2),
      selectedModelId: 'model-1',
      selectedCheckpointId: 'checkpoint-1',
      selectedPresetPromptId: 'prompt-1',
      checkpoints: [
        ChatCheckpoint(
          id: 'checkpoint-1',
          title: '检查点 1',
          content: '总结当前分支的重要上下文。',
          createdAt: DateTime(2026, 4, 27, 10, 1),
          coveredUntilMessageId: 'assistant-2',
          sourceMemoryPromptName: '研发总结',
        ),
      ],
      reasoningEnabled: true,
      reasoningEffort: ReasoningEffort.high,
    );

    await repository.saveConversations([conversation]);
    final restored = repository.loadAll();

    expect(restored, hasLength(1));
    final restoredConv = restored.single;
    expect(restoredConv.id, conversation.id);
    expect(restoredConv.title, conversation.title);
    expect(restoredConv.createdAt, conversation.createdAt);
    expect(restoredConv.updatedAt, conversation.updatedAt);
    expect(restoredConv.selectedModelId, conversation.selectedModelId);
    expect(restoredConv.selectedCheckpointId, conversation.selectedCheckpointId);
    expect(restoredConv.selectedPresetPromptId,
        conversation.selectedPresetPromptId);
    expect(restoredConv.reasoningEnabled, conversation.reasoningEnabled);
    expect(restoredConv.reasoningEffort, conversation.reasoningEffort);
    expect(restoredConv.selectedChildByParentId,
        equals(conversation.selectedChildByParentId));
    expect(restoredConv.excludedMessageIds, conversation.excludedMessageIds);

    // messageNodes: verify count + IDs, spot-check content fields
    expect(restoredConv.messageNodes, hasLength(3));
    final restoredById = {
      for (final n in restoredConv.messageNodes) n.id: n,
    };
    expect(
      restoredById.keys,
      unorderedEquals(conversation.messageNodes.map((n) => n.id)),
    );
    expect(restoredById['assistant-2']?.reasoningContent, '保留思考内容');
    expect(restoredById['user-1']?.userMessageSegments.length, 2);

    // checkpoints: verify count + key fields
    expect(restoredConv.checkpoints, hasLength(1));
    expect(restoredConv.checkpoints.single.id, 'checkpoint-1');
    expect(restoredConv.checkpoints.single.title, '检查点 1');
    expect(restoredConv.checkpoints.single.content, '总结当前分支的重要上下文。');
  });
}
