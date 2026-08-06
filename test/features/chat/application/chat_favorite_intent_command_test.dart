import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_favorite_intent_command.dart';
import 'package:oh_my_llm/features/chat/application/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

/// 记录 add/remove/create 调用的假 [ChatFavoritesFacade]，不依赖 Favorites feature。
class _RecordingFacade implements ChatFavoritesFacade {
  _RecordingFacade(this._snapshot);

  final ChatFavoritesSnapshot _snapshot;
  final added = <ChatFavoriteDraft>[];
  final removedIds = <String>[];
  final createdNames = <String>[];

  @override
  ChatFavoritesSnapshot get snapshot => _snapshot;

  @override
  void add(ChatFavoriteDraft draft) => added.add(draft);

  @override
  String createCollection(String name) {
    createdNames.add(name);
    return 'new-col';
  }

  @override
  void remove(String favoriteId) => removedIds.add(favoriteId);
}

ChatMessage _user(String id, String content) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

ChatMessage _system(String id, String content) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.system,
    content: content,
    createdAt: DateTime(2026, 1, 1),
  );
}

ChatMessage _assistant(
  String id,
  String content, {
  String reasoning = '',
  String assistantModelDisplayName = 'Model',
}) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.assistant,
    content: content,
    reasoningContent: reasoning,
    assistantModelDisplayName: assistantModelDisplayName,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// 按显示顺序把消息连成一条选中路径：首条为 root，后一条父节点指向前一条。
ChatConversation _conversationWithPath(List<ChatMessage> nodes) {
  final connected = <ChatMessage>[
    for (var i = 0; i < nodes.length; i++)
      nodes[i].copyWith(parentId: i == 0 ? null : nodes[i - 1].id),
  ];
  return ChatConversation(
    id: 'conv-1',
    title: '测试对话',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    messageNodes: connected,
  );
}

const _emptySnapshot = ChatFavoritesSnapshot(entries: [], collections: []);

void main() {
  test('无现有收藏时返回 needs-collection 且未调用 add', () {
    final user = _user('user-1', '问题');
    final assistant = _assistant(
      'assistant-1',
      '回复',
      reasoning: '思考',
      assistantModelDisplayName: 'Model-X',
    );
    final conversation = _conversationWithPath([user, assistant]);
    final facade = _RecordingFacade(_emptySnapshot);
    final command = ChatFavoriteIntentCommand(facade);

    final result = command.beginToggle(
      conversation: conversation,
      assistantMessage: assistant,
    );

    expect(result, isA<ChatFavoriteNeedsCollection>());
    final needs = result as ChatFavoriteNeedsCollection;
    expect(needs.draftWithoutCollection.userMessageContent, '问题');
    expect(needs.draftWithoutCollection.assistantContent, '回复');
    expect(needs.draftWithoutCollection.assistantReasoningContent, '思考');
    expect(needs.draftWithoutCollection.assistantModelDisplayName, 'Model-X');
    expect(needs.draftWithoutCollection.collectionId, isNull);
    expect(
      needs.draftWithoutCollection.sourceAssistantMessageId,
      'assistant-1',
    );
    expect(needs.draftWithoutCollection.sourceConversationId, 'conv-1');
    expect(needs.draftWithoutCollection.sourceConversationTitle, '测试对话');
    expect(needs.collectionOptions, isEmpty);
    expect(facade.added, isEmpty);
    expect(facade.removedIds, isEmpty);
  });

  test('参数化锁定 user metadata 三分支 fallback', () {
    final user1 = _user('user-1', '第一条问题');
    final assistant1 = _assistant('assistant-1', '回复一');
    final user2 = _user('user-2', '第二条问题');
    final assistant2 = _assistant('assistant-2', '回复二');
    final absent = _assistant('absent', '不存在');

    final cases = [
      // 前缀有 user：取最近 user（user2，而非更早的 user1）。
      (
        name: '最近 user',
        nodes: [user1, assistant1, user2, assistant2],
        target: assistant2,
        expected: '第二条问题',
      ),
      // 前缀非空但无 user：回退前缀第一条（system）。
      (
        name: '无 user 回退前缀首条',
        nodes: [_system('system-1', '系统提示'), assistant1],
        target: assistant1,
        expected: '系统提示',
      ),
      // assistant 位于索引 0：空字符串。
      (
        name: 'assistant 首条',
        nodes: [assistant1],
        target: assistant1,
        expected: '',
      ),
      // assistant 不在消息列表：索引 -1，空字符串。
      (
        name: 'assistant 不存在',
        nodes: [user1, assistant1],
        target: absent,
        expected: '',
      ),
    ];

    for (final c in cases) {
      final conversation = _conversationWithPath(c.nodes);
      final facade = _RecordingFacade(_emptySnapshot);
      final command = ChatFavoriteIntentCommand(facade);

      final result = command.beginToggle(
        conversation: conversation,
        assistantMessage: c.target,
      );
      final draft =
          (result as ChatFavoriteNeedsCollection).draftWithoutCollection;
      expect(draft.userMessageContent, c.expected, reason: c.name);
    }
  });

  test('已存在收藏时 remove 一次并返回完整 entry；restore 用原 draft 恢复', () {
    final user = _user('user-1', '问题');
    final assistant = _assistant('assistant-1', '回复');
    final conversation = _conversationWithPath([user, assistant]);
    final draft = ChatFavoriteDraft(
      userMessageContent: '问题',
      assistantContent: '回复',
      assistantReasoningContent: '思考',
      assistantModelDisplayName: 'Model',
      collectionId: 'col-1',
      sourceAssistantMessageId: 'assistant-1',
      sourceConversationId: 'conv-1',
      sourceConversationTitle: '测试对话',
    );
    final entry = ChatFavoriteEntry(id: 'favorite-1', draft: draft);
    final facade = _RecordingFacade(
      ChatFavoritesSnapshot(entries: [entry], collections: []),
    );
    final command = ChatFavoriteIntentCommand(facade);

    final result = command.beginToggle(
      conversation: conversation,
      assistantMessage: assistant,
    );

    expect(result, isA<ChatFavoriteRemoved>());
    final removed = result as ChatFavoriteRemoved;
    expect(removed.removedEntry.id, 'favorite-1');
    expect(facade.removedIds, ['favorite-1']);
    expect(facade.added, isEmpty);

    command.restore(removed.removedEntry);

    expect(facade.added, hasLength(1));
    final restored = facade.added.single;
    expect(restored.userMessageContent, '问题');
    expect(restored.assistantContent, '回复');
    expect(restored.assistantReasoningContent, '思考');
    expect(restored.assistantModelDisplayName, 'Model');
    expect(restored.collectionId, 'col-1');
    expect(restored.sourceAssistantMessageId, 'assistant-1');
    expect(restored.sourceConversationId, 'conv-1');
    expect(restored.sourceConversationTitle, '测试对话');
  });

  test('addToCollection 的 "" 转 null、正常 ID 原样', () {
    final facade = _RecordingFacade(_emptySnapshot);
    final command = ChatFavoriteIntentCommand(facade);
    const base = ChatFavoriteDraft(
      userMessageContent: '问题',
      assistantContent: '回复',
      assistantReasoningContent: '',
      assistantModelDisplayName: 'Model',
      collectionId: null,
      sourceAssistantMessageId: null,
      sourceConversationId: null,
      sourceConversationTitle: null,
    );

    command.addToCollection(base, '');
    expect(facade.added.single.collectionId, isNull);

    command.addToCollection(base, 'col-1');
    expect(facade.added.last.collectionId, 'col-1');
    expect(facade.added, hasLength(2));
  });

  test('createCollection 委托一次；空 trimmed name 不产生空收藏夹', () {
    final facade = _RecordingFacade(_emptySnapshot);
    final command = ChatFavoriteIntentCommand(facade);

    expect(command.createCollection('  新夹  '), 'new-col');
    expect(facade.createdNames, ['新夹']);

    expect(command.createCollection('   '), isNull);
    expect(command.createCollection(''), isNull);
    expect(facade.createdNames, ['新夹']);
  });
}
