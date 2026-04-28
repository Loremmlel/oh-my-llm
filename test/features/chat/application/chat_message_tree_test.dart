import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_message_tree.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── 辅助函数 ─────────────────────────────────────────────────────────────

  ChatMessage _msg(
    String id, {
    String? parentId,
    ChatMessageRole role = ChatMessageRole.user,
    String content = '',
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content.isEmpty ? id : content,
      createdAt: DateTime(2026),
      parentId: parentId,
    );
  }

  ChatConversation _conv({
    List<ChatMessage> messages = const [],
    List<ChatMessage> messageNodes = const [],
    Map<String, String> selections = const {},
  }) {
    return ChatConversation(
      id: 'conv',
      messages: messages,
      messageNodes: messageNodes,
      selectedChildByParentId: selections,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  // ── resolveMessageTreeState ───────────────────────────────────────────────

  group('resolveMessageTreeState', () {
    test('空 messageNodes：线性消息序列转为树', () {
      final conv = _conv(
        messages: [
          _msg('u1', role: ChatMessageRole.user),
          _msg('a1', role: ChatMessageRole.assistant),
        ],
      );

      final state = resolveMessageTreeState(conv);

      expect(state.nodes, hasLength(2));
      expect(state.nodes[0].parentId, rootConversationParentId);
      expect(state.nodes[1].parentId, 'u1');
      expect(state.selections[rootConversationParentId], 'u1');
      expect(state.selections['u1'], 'a1');
    });

    test('空 messageNodes 且消息列表为空：返回空树', () {
      final state = resolveMessageTreeState(_conv());

      expect(state.nodes, isEmpty);
      expect(state.selections, isEmpty);
    });

    test('已有 messageNodes：直接复用，不重建', () {
      final nodes = [
        _msg('u1', parentId: rootConversationParentId),
        _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        _msg('a2', parentId: 'u1', role: ChatMessageRole.assistant),
      ];
      final conv = _conv(
        messageNodes: nodes,
        selections: {rootConversationParentId: 'u1', 'u1': 'a2'},
      );

      final state = resolveMessageTreeState(conv);

      expect(state.nodes, hasLength(3));
      expect(state.selections['u1'], 'a2');
    });

    test('返回的 nodes/selections 是可变副本，不影响原会话', () {
      final conv = _conv(
        messageNodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      );

      final state = resolveMessageTreeState(conv);
      state.nodes.add(_msg('extra'));
      state.selections['new'] = 'value';

      expect(conv.messageNodes, hasLength(1));
      expect(conv.selectedChildByParentId, hasLength(1));
    });
  });

  // ── appendNodeToTree ──────────────────────────────────────────────────────

  group('appendNodeToTree', () {
    test('追加节点并更新父级选中映射', () {
      final initial = resolveMessageTreeState(_conv(
        messageNodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      ));

      final next = appendNodeToTree(
        treeState: initial,
        node: _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        parentId: 'u1',
      );

      expect(next.nodes, hasLength(2));
      expect(next.nodes.last.id, 'a1');
      expect(next.selections['u1'], 'a1');
    });

    test('追加根级节点时更新 root 选中', () {
      const initial = ChatMessageTreeState(nodes: [], selections: {});

      final next = appendNodeToTree(
        treeState: initial,
        node: _msg('u1', parentId: rootConversationParentId),
        parentId: rootConversationParentId,
      );

      expect(next.selections[rootConversationParentId], 'u1');
    });

    test('追加第二个兄弟节点：选中映射切换到新节点', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = appendNodeToTree(
        treeState: initial,
        node: _msg('a2', parentId: 'u1', role: ChatMessageRole.assistant),
        parentId: 'u1',
      );

      expect(next.nodes, hasLength(3));
      expect(next.selections['u1'], 'a2');
      // 根选中保持不变。
      expect(next.selections[rootConversationParentId], 'u1');
    });

    test('不修改原 treeState', () {
      final initial = ChatMessageTreeState(
        nodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      );

      appendNodeToTree(
        treeState: initial,
        node: _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        parentId: 'u1',
      );

      expect(initial.nodes, hasLength(1));
      expect(initial.selections, hasLength(1));
    });
  });

  // ── replaceAssistantMessageInTree ─────────────────────────────────────────

  group('replaceAssistantMessageInTree', () {
    test('正常替换目标消息内容与 streaming 标志', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          ChatMessage(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '旧内容',
            reasoningContent: '旧推理',
            isStreaming: true,
            createdAt: DateTime(2026),
            parentId: 'u1',
          ),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = replaceAssistantMessageInTree(
        treeState: initial,
        assistantMessageId: 'a1',
        nextContent: '新内容',
        nextReasoningContent: '新推理',
        isStreaming: false,
      );

      final replaced = next.nodes.firstWhere((n) => n.id == 'a1');
      expect(replaced.content, '新内容');
      expect(replaced.reasoningContent, '新推理');
      expect(replaced.isStreaming, isFalse);
    });

    test('目标 id 不存在时：节点列表原封不动', () {
      final initial = ChatMessageTreeState(
        nodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      );

      final next = replaceAssistantMessageInTree(
        treeState: initial,
        assistantMessageId: 'nonexistent',
        nextContent: 'x',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(next.nodes.single.id, 'u1');
    });

    test('只替换目标节点，其余节点内容不受影响', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId, content: '用户原始'),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = replaceAssistantMessageInTree(
        treeState: initial,
        assistantMessageId: 'a1',
        nextContent: '新回复',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(next.nodes.firstWhere((n) => n.id == 'u1').content, '用户原始');
    });

    test('选中映射在替换后保持不变', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = replaceAssistantMessageInTree(
        treeState: initial,
        assistantMessageId: 'a1',
        nextContent: '新回复',
        nextReasoningContent: '',
        isStreaming: false,
      );

      expect(next.selections, equals(initial.selections));
    });
  });

  // ── removeNodeFromTree ────────────────────────────────────────────────────

  group('removeNodeFromTree', () {
    test('删除叶子节点：节点移除，选中映射对应条目消失', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'a1');

      expect(next.nodes.map((n) => n.id), equals(['u1']));
      expect(next.selections.containsKey('u1'), isFalse);
      // root → u1 的选中仍然保留。
      expect(next.selections[rootConversationParentId], 'u1');
    });

    test('删除中间节点：该节点及其全部后代一并移除', () {
      // 树形：root → u1 → a1 → u2 → a2
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
          _msg('u2', parentId: 'a1'),
          _msg('a2', parentId: 'u2', role: ChatMessageRole.assistant),
        ],
        selections: {
          rootConversationParentId: 'u1',
          'u1': 'a1',
          'a1': 'u2',
          'u2': 'a2',
        },
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'a1');

      expect(next.nodes.map((n) => n.id), equals(['u1']));
      expect(next.selections.containsKey('a1'), isFalse);
      expect(next.selections.containsKey('u2'), isFalse);
      expect(next.selections[rootConversationParentId], 'u1');
    });

    test('删除根节点（唯一节点）：树变为空', () {
      final initial = ChatMessageTreeState(
        nodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'u1');

      expect(next.nodes, isEmpty);
      expect(next.selections, isEmpty);
    });

    test('多分支：删除一侧分支不影响另一侧', () {
      // root → u1 → a1（旧分支）
      //           ↘ a2（当前选中）
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
          _msg('a2', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a2'},
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'a1');

      expect(next.nodes.map((n) => n.id), containsAll(['u1', 'a2']));
      expect(next.nodes, hasLength(2));
      expect(next.selections['u1'], 'a2');
    });

    test('删除当前选中的 value 节点：对应 selection 条目清除', () {
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('u1', parentId: rootConversationParentId),
          _msg('a1', parentId: 'u1', role: ChatMessageRole.assistant),
        ],
        selections: {rootConversationParentId: 'u1', 'u1': 'a1'},
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'a1');

      // value 'a1' 被删除，{'u1': 'a1'} 条目应移除。
      expect(next.selections.containsKey('u1'), isFalse);
    });

    test('删除不存在的节点：树状态不变', () {
      final initial = ChatMessageTreeState(
        nodes: [_msg('u1', parentId: rootConversationParentId)],
        selections: {rootConversationParentId: 'u1'},
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'ghost');

      expect(next.nodes.map((n) => n.id), equals(['u1']));
      expect(next.selections, equals(initial.selections));
    });

    test('深层嵌套：删除顶层节点后所有后代递归清除', () {
      // root → n1 → n2 → n3 → n4
      final initial = ChatMessageTreeState(
        nodes: [
          _msg('n1', parentId: rootConversationParentId),
          _msg('n2', parentId: 'n1'),
          _msg('n3', parentId: 'n2'),
          _msg('n4', parentId: 'n3'),
        ],
        selections: {
          rootConversationParentId: 'n1',
          'n1': 'n2',
          'n2': 'n3',
          'n3': 'n4',
        },
      );

      final next = removeNodeFromTree(treeState: initial, nodeId: 'n1');

      expect(next.nodes, isEmpty);
      expect(next.selections, isEmpty);
    });
  });
}
