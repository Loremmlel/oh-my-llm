import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/sessions/chat_message_tree.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  final baseTime = DateTime(2026, 5, 26, 12);

  ChatMessage node(
    String id,
    String parentId,
    ChatMessageRole role,
    String content, {
    String reasoningContent = '',
    bool isStreaming = false,
  }) => ChatMessage(
    id: id,
    role: role,
    content: content,
    createdAt: baseTime,
    parentId: parentId,
    reasoningContent: reasoningContent,
    isStreaming: isStreaming,
  );

  ChatConversation conversation({
    List<ChatMessage> nodes = const [],
    Map<String, String> selections = const {},
  }) => ChatConversation(
    id: 'conversation',
    messageNodes: nodes,
    selectedChildByParentId: selections,
    createdAt: baseTime,
    updatedAt: baseTime,
  );

  group('resolveMessageTreeState', () {
    test('复制已有节点和选择映射，不与会话共享可变容器', () {
      final source = conversation(
        nodes: [
          node('u1', rootConversationParentId, ChatMessageRole.user, '你好'),
        ],
        selections: {rootConversationParentId: 'u1'},
      );

      final result = resolveMessageTreeState(source);

      expect(result.nodes, source.messageNodes);
      expect(result.selections, source.selectedChildByParentId);
      expect(identical(result.nodes, source.messageNodes), isFalse);
      expect(
        identical(result.selections, source.selectedChildByParentId),
        isFalse,
      );
    });

    test('空会话返回空树', () {
      final result = resolveMessageTreeState(conversation());

      expect(result.nodes, isEmpty);
      expect(result.selections, isEmpty);
    });
  });

  test('appendNodeToTree 追加节点、切换父节点选择并保留其他选择', () {
    final tree = ChatMessageTreeState(
      nodes: [
        node('u1', rootConversationParentId, ChatMessageRole.user, '你好'),
        node('a1', 'u1', ChatMessageRole.assistant, '旧回复'),
      ],
      selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
    );
    final branch = node('a2', 'u1', ChatMessageRole.assistant, '新回复');

    final result = appendNodeToTree(
      treeState: tree,
      node: branch,
      parentId: 'u1',
    );

    expect(result.nodes.map((item) => item.id), ['u1', 'a1', 'a2']);
    expect(result.selections, {rootConversationParentId: 'u1', 'u1': 'a2'});
  });

  group('replaceAssistantMessageInTree', () {
    test('只替换匹配节点的正文、推理和流式状态', () {
      final originalUser = node(
        'u1',
        rootConversationParentId,
        ChatMessageRole.user,
        '用户消息',
      );
      final tree = ChatMessageTreeState(
        nodes: [
          originalUser,
          node(
            'a1',
            'u1',
            ChatMessageRole.assistant,
            '旧正文',
            reasoningContent: '旧推理',
            isStreaming: true,
          ),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'a1',
        nextContent: '新正文',
        nextReasoningContent: '新推理',
        isStreaming: false,
      );

      expect(result.nodes.first, originalUser);
      expect(result.nodes.last.content, '新正文');
      expect(result.nodes.last.reasoningContent, '新推理');
      expect(result.nodes.last.isStreaming, isFalse);
      expect(result.selections, tree.selections);
    });

    test('目标 ID 不存在时节点内容保持不变', () {
      final tree = ChatMessageTreeState(
        nodes: [node('a1', 'u1', ChatMessageRole.assistant, '旧正文')],
        selections: const {},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'missing',
        nextContent: '新正文',
        nextReasoningContent: '新推理',
        isStreaming: false,
      );

      expect(result.nodes, tree.nodes);
    });
  });

  group('removeNodeFromTree', () {
    test('删除叶子节点并清理指向它的选择', () {
      final tree = ChatMessageTreeState(
        nodes: [
          node('u1', rootConversationParentId, ChatMessageRole.user, '用户'),
          node('a1', 'u1', ChatMessageRole.assistant, '回复'),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      expect(result.nodes.map((item) => item.id), ['u1']);
      expect(result.selections, {rootConversationParentId: 'u1'});
    });

    test('级联删除目标分支全部后代，同时保留兄弟分支及其有效选择', () {
      final tree = ChatMessageTreeState(
        nodes: [
          node('u1', rootConversationParentId, ChatMessageRole.user, '用户'),
          node('a1', 'u1', ChatMessageRole.assistant, '分支 A'),
          node('a2', 'u1', ChatMessageRole.assistant, '分支 B'),
          node('u2', 'a1', ChatMessageRole.user, '后续用户'),
          node('a3', 'u2', ChatMessageRole.assistant, '后续回复'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
          'a1': 'u2',
          'u2': 'a3',
          'a2': 'external-selection',
        },
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      expect(result.nodes.map((item) => item.id), ['u1', 'a2']);
      expect(result.selections, {
        rootConversationParentId: 'u1',
        'a2': 'external-selection',
      });
    });

    test('删除不存在的 ID 时树内容保持不变', () {
      final tree = ChatMessageTreeState(
        nodes: [
          node('u1', rootConversationParentId, ChatMessageRole.user, '用户'),
        ],
        selections: {rootConversationParentId: 'u1'},
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'missing');

      expect(result.nodes, tree.nodes);
      expect(result.selections, tree.selections);
    });
  });
}
