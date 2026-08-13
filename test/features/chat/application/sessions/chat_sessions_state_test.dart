import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────

  /// 创建测试用 [ChatMessage]。
  ChatMessage createMsg({
    required String id,
    required ChatMessageRole role,
    required String content,
    String reasoningContent = '',
    String? parentId,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      reasoningContent: reasoningContent,
      createdAt: DateTime(2026, 1, 1),
      parentId: parentId,
      isStreaming: isStreaming,
    );
  }

  /// 创建测试用 [ChatConversation]，messageNodes 同时作为 messages 传入，
  /// 避免 fromJson 补全线性树逻辑干扰测试。
  ChatConversation createConv({
    required String id,
    required List<ChatMessage> messageNodes,
    Map<String, String>? selections,
  }) {
    return ChatConversation(
      id: id,
      messageNodes: messageNodes,
      selectedChildByParentId: selections ?? {},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  /// 创建测试用 [ChatStreamingReply]。
  ChatStreamingReply createReply({
    String conversationId = 'conv-1',
    String assistantMessageId = 'a1',
    String content = '流式内容',
    String reasoningContent = '',
  }) {
    return ChatStreamingReply(
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      content: content,
      reasoningContent: reasoningContent,
    );
  }

  // ── applyStreamingReplyToConversation ───────────────────

  group('applyStreamingReplyToConversation', () {
    test('streamingReply 为 null 时返回原会话不变', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(id: 'u1', role: ChatMessageRole.user, content: '你好'),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: null,
      );

      expect(result, equals(conv));
    });

    test('streamingReply.conversationId 与会话 id 不匹配时返回原会话', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(id: 'a1', role: ChatMessageRole.assistant, content: '原内容'),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(
          conversationId: 'conv-other',
          assistantMessageId: 'a1',
        ),
      );

      expect(result, equals(conv));
    });

    test('匹配的 reply 同时更新 assistant 正文与推理', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '旧正文',
            reasoningContent: '旧推理',
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '新正文', reasoningContent: '新推理'),
      );

      final replacedNode = result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.content, '新正文');
      expect(replacedNode.reasoningContent, '新推理');
    });

    test('isStreaming=true 时消息上的 isStreaming 标记为 true', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '',
            isStreaming: false,
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '流式内容...'),
        isStreaming: true,
      );

      final replacedNode = result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.isStreaming, isTrue);
    });

    test('isStreaming=false 时消息上的 isStreaming 标记为 false', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '完整的回复',
            isStreaming: true,
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '完整的回复'),
        isStreaming: false,
      );

      final replacedNode = result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.isStreaming, isFalse);
    });
  });
}
