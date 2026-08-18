import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';

void main() {
  test('前台通知复用聊天字数规则统计中英文内容', () {
    const snapshot = ChatGenerationSnapshot(
      generationId: 1,
      conversationId: 'conv-1',
      attempt: 1,
      phase: ChatGenerationPhase.streaming,
      outcome: null,
    );
    const reply = ChatStreamingReply(
      conversationId: 'conv-1',
      assistantMessageId: 'assistant-1',
      content: 'hello world',
      reasoningContent: '你好 test',
    );

    final projection = const ChatGenerationNotificationProjector().project(
      snapshot: snapshot,
      streamingReply: reply,
    );

    expect(projection.counts.content, 2);
    expect(projection.counts.reasoning, 3);
    expect(projection.payload.text, '正文 2 字 · 推理 3 字');
  });
}
