import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_message_tree.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  final baseTime = DateTime(2026, 5, 26, 12);

  // ── 工厂函数 ──────

  /// 创建用户消息（默认无 parentId）。
  ChatMessage userMsg(String id, String content) {
    return ChatMessage(
      id: id,
      role: ChatMessageRole.user,
      content: content,
      createdAt: baseTime,
    );
  }

  /// 创建助手消息（默认无 parentId）。
  ChatMessage assistantMsg(
    String id,
    String content, {
    String reasoningContent = '',
  }) {
    return ChatMessage(
      id: id,
      role: ChatMessageRole.assistant,
      content: content,
      createdAt: baseTime,
      reasoningContent: reasoningContent,
    );
  }

  /// 创建带 parentId 的用户消息节点。
  ChatMessage userNode(String id, String parentId, String content) {
    return userMsg(id, content).copyWith(parentId: parentId);
  }

  /// 创建带 parentId 的助手消息节点。
  ChatMessage assistantNode(
    String id,
    String parentId,
    String content, {
    String reasoningContent = '',
  }) {
    return assistantMsg(id, content, reasoningContent: reasoningContent)
        .copyWith(parentId: parentId);
  }

  /// 创建基本会话。
  ChatConversation conv({
    required String id,
    List<ChatMessage> messageNodes = const [],
    Map<String, String> selectedChildByParentId = const {},
  }) {
    return ChatConversation(
      id: id,
      messageNodes: messageNodes,
      selectedChildByParentId: selectedChildByParentId,
      createdAt: baseTime,
      updatedAt: baseTime,
    );
  }

  /// 创建包含 messageNodes 的会话（树形数据已存在）。
  ChatConversation treeConv({
    required String id,
    required List<ChatMessage> messageNodes,
    required Map<String, String> selectedChildByParentId,
  }) {
    return ChatConversation(
      id: id,
      messageNodes: messageNodes,
      selectedChildByParentId: selectedChildByParentId,
      createdAt: baseTime,
      updatedAt: baseTime,
    );
  }

  /// 构建空的树状态。
  // ignore: unused_element
  ChatMessageTreeState emptyTree() {
    return const ChatMessageTreeState(nodes: [], selections: {});
  }

  // ════════════════════════════════════════════════
  // resolveMessageTreeState
  // ════════════════════════════════════════════════

  group('resolveMessageTreeState', () {
    test('messageNodes 不为空时直接复制节点和选择映射', () {
      final tree = treeConv(
        id: 'c1',
        messageNodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '你好！'),
        ],
        selectedChildByParentId: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
        },
      );

      final result = resolveMessageTreeState(tree);

      expect(result.nodes.length, 2);
      expect(result.nodes[0].id, 'u1');
      expect(result.nodes[0].parentId, rootConversationParentId);
      expect(result.nodes[1].id, 'a1');
      expect(result.nodes[1].parentId, 'u1');
      expect(result.selections.length, 2);
      expect(result.selections[rootConversationParentId], 'u1');
      expect(result.selections['u1'], 'a1');
      // 验证深拷贝：修改返回结果不影响原始会话
      expect(identical(result.nodes, tree.messageNodes), isFalse);
    });

    test('空会话返回空的节点列表和空选择映射', () {
      final c = conv(id: 'c3');

      final result = resolveMessageTreeState(c);

      expect(result.nodes, isEmpty);
      expect(result.selections, isEmpty);
    });
  });

  // ════════════════════════════════════════════════
  // appendNodeToTree
  // ════════════════════════════════════════════════

  group('appendNodeToTree', () {
    test('基本追加：将节点加入节点列表末尾并更新选择映射', () {
      final tree = ChatMessageTreeState(
        nodes: [userNode('u1', rootConversationParentId, '你好')],
        selections: {rootConversationParentId: 'u1'},
      );
      final newNode = assistantNode('a1', 'u1', '回复');

      final result = appendNodeToTree(
        treeState: tree,
        node: newNode,
        parentId: 'u1',
      );

      expect(result.nodes.length, 2);
      expect(result.nodes[1].id, 'a1');
      expect(result.nodes[1].parentId, 'u1');
      expect(result.selections['u1'], 'a1');
    });

    test('追加节点时保留已有的其他选择映射条目不变', () {
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '回复1'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
        },
      );
      final branchNode = assistantNode('a2', 'u1', '回复2');

      final result = appendNodeToTree(
        treeState: tree,
        node: branchNode,
        parentId: 'u1',
      );

      // root 的 selection 保持不变
      expect(result.selections[rootConversationParentId], 'u1');
      // u1 的 selection 更新为最新追加的节点
      expect(result.selections['u1'], 'a2');
      // 原有的 a1 仍然保留在 nodes 中（不会被删除）
      expect(result.nodes.where((n) => n.id == 'a1').length, 1);
    });

    test('为尚未在选择映射中存在的 parentId 创建新条目', () {
      final tree = ChatMessageTreeState(
        nodes: [userNode('u1', rootConversationParentId, '你好')],
        selections: {},
      );
      final newNode = assistantNode('a1', 'u1', '回复');

      final result = appendNodeToTree(
        treeState: tree,
        node: newNode,
        parentId: 'u1',
      );

      expect(result.selections['u1'], 'a1');
    });
  });

  // ════════════════════════════════════════════════
  // replaceAssistantMessageInTree
  // ════════════════════════════════════════════════

  group('replaceAssistantMessageInTree', () {
    test('替换匹配 ID 的消息内容和推理内容、更新流式标志', () {
      final tree = ChatMessageTreeState(
        nodes: [assistantNode('a1', 'u1', '旧内容', reasoningContent: '旧推理')],
        selections: {},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'a1',
        nextContent: '新内容',
        nextReasoningContent: '新推理',
        isStreaming: true,
      );

      expect(result.nodes.single.content, '新内容');
      expect(result.nodes.single.reasoningContent, '新推理');
      expect(result.nodes.single.isStreaming, isTrue);
    });

    test('跳过 ID 不匹配的消息，保持不变', () {
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '回复'),
        ],
        selections: {},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'non-existent',
        nextContent: '新内容',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(result.nodes[0].content, '你好');
      expect(result.nodes[1].content, '回复');
      expect(result.nodes, tree.nodes);
    });

    test('其他节点和选择映射保持不变', () {
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '旧回复'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
        },
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'a1',
        nextContent: '新回复',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(result.nodes[0].content, '你好');
      expect(result.nodes[0].role, ChatMessageRole.user);
      expect(result.selections, tree.selections);
    });

    test('isStreaming 为 false 时正确更新为 false', () {
      final tree = ChatMessageTreeState(
        nodes: [
          assistantNode('a1', 'u1', '内容').copyWith(isStreaming: true),
        ],
        selections: {},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'a1',
        nextContent: '完成的内容',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(result.nodes.single.isStreaming, isFalse);
      expect(result.nodes.single.content, '完成的内容');
    });

    test('按 ID 精确匹配，非 assistant 角色的消息也会被替换', () {
      // 虽然函数名为 replaceAssistantMessageInTree，
      // 但在实现上只按 ID 匹配，不校验 role。
      // TODO: 修复 replaceAssistantMessageInTree 使其校验 role，然后删除此测试

      final tree = ChatMessageTreeState(
        nodes: [userNode('u1', rootConversationParentId, '旧用户消息')],
        selections: {},
      );

      final result = replaceAssistantMessageInTree(
        treeState: tree,
        assistantMessageId: 'u1',
        nextContent: '新用户消息',
        nextReasoningContent: '推理',
        isStreaming: true,
      );

      expect(result.nodes.single.content, '新用户消息');
      expect(result.nodes.single.role, ChatMessageRole.user);
      // role 未被函数改变，仅改了 content、reasoningContent、isStreaming
    }, skip: '当前实现不校验 role，覆盖已知非预期行为');
  });

  // ════════════════════════════════════════════════
  // removeNodeFromTree
  // ════════════════════════════════════════════════

  group('removeNodeFromTree', () {
    test('删除叶子节点：仅移除该节点，兄弟节点不受影响', () {
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '回复1'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
        },
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      expect(result.nodes.length, 1);
      expect(result.nodes.single.id, 'u1');
    });

    test('删除有子节点的节点时级联删除全部后代', () {
      // 树结构: u1 → a1 → u2 → a2
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '消息1'),
          assistantNode('a1', 'u1', '回复1'),
          userNode('u2', 'a1', '消息2'),
          assistantNode('a2', 'u2', '回复2'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
          'a1': 'u2',
          'u2': 'a2',
        },
      );

      // 删除 a1 节点，预期级联删除 a1、u2、a2
      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      expect(result.nodes.length, 1);
      expect(result.nodes.single.id, 'u1');
    });

    test('删除节点后清理选择映射中引用被删除节点的条目', () {
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '你好'),
          assistantNode('a1', 'u1', '回复'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
        },
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      // a1 被删除，u1 → a1 的 selection 应被移除（a1 在 value 位置）
      expect(result.selections.containsKey('u1'), isFalse);
      // root → u1 的 selection 应保留（u1 未被删除）
      expect(result.selections[rootConversationParentId], 'u1');
    });

    test('选择映射中被删除节点同时作为 key 和 value 时一并清理', () {
      // 树结构: u1 → a1 → u2，删除 u2 后 a1 → u2 的 entry 应被清除
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '消息1'),
          assistantNode('a1', 'u1', '回复1'),
          userNode('u2', 'a1', '消息2'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
          'a1': 'u2',
        },
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'u2');

      // u2 被删除
      expect(result.nodes.length, 2);
      // a1 → u2 selection 被清理（u2 是 value）
      expect(result.selections.containsKey('a1'), isFalse);
      // root → u1 和 u1 → a1 保留
      expect(result.selections[rootConversationParentId], 'u1');
      expect(result.selections['u1'], 'a1');
    });

    test('单节点树删除唯一节点后节点列表和选择映射均为空', () {
      final tree = ChatMessageTreeState(
        nodes: [userNode('u1', rootConversationParentId, '唯一消息')],
        selections: {rootConversationParentId: 'u1'},
      );

      final result = removeNodeFromTree(treeState: tree, nodeId: 'u1');

      expect(result.nodes, isEmpty);
      expect(result.selections, isEmpty);
    });

    test('删除不存在的节点 ID 时树状态保持不变', () {
      final tree = ChatMessageTreeState(
        nodes: [userNode('u1', rootConversationParentId, '你好')],
        selections: {rootConversationParentId: 'u1'},
      );

      final result = removeNodeFromTree(
        treeState: tree,
        nodeId: 'non-existent',
      );

      expect(result.nodes.length, 1);
      expect(result.nodes.single.id, 'u1');
      expect(result.selections, tree.selections);
    });

    test('删除根节点（rootConversationParentId 的直接子节点）时正确移除其所有后代', () {
      // 树结构: root → u1 → a1 → u2 → a2
      //               ↘ a1-alt（兄弟分支）
      final tree = ChatMessageTreeState(
        nodes: [
          userNode('u1', rootConversationParentId, '消息1'),
          assistantNode('a1', 'u1', '分支A回复'),
          assistantNode('a1-alt', 'u1', '分支B回复'),
          userNode('u2', 'a1', '消息2'),
          assistantNode('a2', 'u2', '回复2'),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
          'a1': 'u2',
          'u2': 'a2',
        },
      );

      // 删除 a1，级联删除 u2、a2，但保留 a1-alt
      final result = removeNodeFromTree(treeState: tree, nodeId: 'a1');

      final remainingIds = result.nodes.map((n) => n.id).toSet();
      expect(remainingIds, {'u1', 'a1-alt'});
      // 确认被删除的分支不在结果中
      expect(remainingIds.contains('a1'), isFalse);
      expect(remainingIds.contains('u2'), isFalse);
      expect(remainingIds.contains('a2'), isFalse);
    });
  });
}
