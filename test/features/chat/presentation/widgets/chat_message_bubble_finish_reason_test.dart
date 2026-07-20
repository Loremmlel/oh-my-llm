import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/chat_message_bubble.dart';

ChatMessage _assistantMessage({
  String content = '正文',
  String? finishReason,
  bool isStreaming = false,
}) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.assistant,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
    finishReason: finishReason,
    isStreaming: isStreaming,
  );
}

Future<void> _pumpBubble(WidgetTester tester, ChatMessage message) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageBubble(message: message),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('finish_reason chip', () {
    testWidgets('finishReason 为 null 时不显示 chip', (tester) async {
      await _pumpBubble(tester, _assistantMessage(finishReason: null));
      expect(find.text('stop'), findsNothing);
      expect(find.text('length'), findsNothing);
    });

    testWidgets("finishReason 为 'stop' 时显示包含 stop 文字的 chip",
        (tester) async {
      await _pumpBubble(tester, _assistantMessage(finishReason: 'stop'));
      expect(find.text('stop'), findsOneWidget);
    });

    testWidgets("finishReason 为 'length' 时显示包含 length 文字的 chip",
        (tester) async {
      await _pumpBubble(tester, _assistantMessage(finishReason: 'length'));
      expect(find.text('length'), findsOneWidget);
    });

    testWidgets('isStreaming 为 true 时不显示 chip（即使 finishReason 非 null）',
        (tester) async {
      await _pumpBubble(
        tester,
        _assistantMessage(finishReason: 'stop', isStreaming: true),
      );
      expect(find.text('stop'), findsNothing);
    });
  });
}
