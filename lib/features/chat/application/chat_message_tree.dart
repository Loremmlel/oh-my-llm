import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

/// 消息树状态，包含当前节点序列与父子选择映射。
class ChatMessageTreeState {
  const ChatMessageTreeState({required this.nodes, required this.selections});

  final List<ChatMessage> nodes;
  final Map<String, String> selections;
}

/// 从会话中恢复可编辑的消息树状态。
ChatMessageTreeState resolveMessageTreeState(ChatConversation conversation) {
  if (conversation.messageNodes.isNotEmpty) {
    return ChatMessageTreeState(
      nodes: List<ChatMessage>.from(conversation.messageNodes),
      selections: Map<String, String>.from(
        conversation.selectedChildByParentId,
      ),
    );
  }

  final nodes = <ChatMessage>[];
  final selections = <String, String>{};
  var parentId = rootConversationParentId;
  for (final message in conversation.messages) {
    final node = message.copyWith(parentId: parentId);
    nodes.add(node);
    selections[parentId] = node.id;
    parentId = node.id;
  }
  return ChatMessageTreeState(nodes: nodes, selections: selections);
}

/// 向当前消息树追加一个节点，并同步更新选中分支。
ChatMessageTreeState appendNodeToTree({
  required ChatMessageTreeState treeState,
  required ChatMessage node,
  required String parentId,
}) {
  final nextNodes = [...treeState.nodes, node];
  final nextSelections = Map<String, String>.from(treeState.selections);
  nextSelections[parentId] = node.id;
  return ChatMessageTreeState(nodes: nextNodes, selections: nextSelections);
}

/// 在消息树中替换某条 assistant 消息的内容。
ChatMessageTreeState replaceAssistantMessageInTree({
  required ChatMessageTreeState treeState,
  required String assistantMessageId,
  required String nextContent,
  required String nextReasoningContent,
  required bool isStreaming,
}) {
  final nextNodes = treeState.nodes
      .map((message) {
        if (message.id != assistantMessageId) {
          return message;
        }

        return message.copyWith(
          content: nextContent,
          reasoningContent: nextReasoningContent,
          isStreaming: isStreaming,
        );
      })
      .toList(growable: false);
  return ChatMessageTreeState(
    nodes: nextNodes,
    selections: Map<String, String>.from(treeState.selections),
  );
}

/// 从消息树中删除某个节点及其全部后代。
ChatMessageTreeState removeNodeFromTree({
  required ChatMessageTreeState treeState,
  required String nodeId,
}) {
  final childIdsByParent = <String, List<String>>{};
  for (final node in treeState.nodes) {
    final parentId = node.parentId ?? rootConversationParentId;
    childIdsByParent.putIfAbsent(parentId, () => <String>[]).add(node.id);
  }

  final removedNodeIds = <String>{};
  final queue = <String>[nodeId];
  while (queue.isNotEmpty) {
    final currentId = queue.removeLast();
    if (!removedNodeIds.add(currentId)) {
      continue;
    }
    queue.addAll(childIdsByParent[currentId] ?? const []);
  }

  final nextNodes = treeState.nodes
      .where((node) => !removedNodeIds.contains(node.id))
      .toList(growable: false);
  final nextSelections = Map<String, String>.from(treeState.selections)
    ..removeWhere((key, value) {
      return removedNodeIds.contains(key) || removedNodeIds.contains(value);
    });
  return ChatMessageTreeState(nodes: nextNodes, selections: nextSelections);
}
