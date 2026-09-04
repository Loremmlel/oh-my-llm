import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_generation_usage.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';

ChatMessage _assistantMessage({
  String content = '正文',
  String? finishReason,
  bool isStreaming = false,
  ChatGenerationUsage? tokenUsage,
}) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.assistant,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
    finishReason: finishReason,
    isStreaming: isStreaming,
    tokenUsage: tokenUsage,
  );
}

Future<void> _pumpBubble(
  WidgetTester tester,
  ChatMessage message, {
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ChatMessageBubble(message: message)),
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

    testWidgets('非空 finishReason 显示对应的 stop / length chip', (tester) async {
      await _pumpBubble(tester, _assistantMessage(finishReason: 'stop'));
      expect(find.text('stop'), findsOneWidget);

      await _pumpBubble(tester, _assistantMessage(finishReason: 'length'));
      expect(find.text('length'), findsOneWidget);
    });

    testWidgets('isStreaming 为 true 时不显示 chip（即使 finishReason 非 null）', (
      tester,
    ) async {
      await _pumpBubble(
        tester,
        _assistantMessage(finishReason: 'stop', isStreaming: true),
      );
      expect(find.text('stop'), findsNothing);
    });
  });

  group('Token 用量', () {
    testWidgets('终态助手消息按固定顺序显示已知值并保留显式 0', (tester) async {
      for (final width in [320.0, 800.0]) {
        await _pumpBubble(
          tester,
          _assistantMessage(
            tokenUsage: const ChatGenerationUsage(
              inputTokens: 4000,
              cachedInputTokens: 1500,
              cacheWriteInputTokens: 800,
              outputTokens: 0,
            ),
          ),
          width: width,
        );

        expect(find.text('输入 4,000'), findsOneWidget, reason: '$width');
        expect(find.text('缓存命中 1,500'), findsOneWidget, reason: '$width');
        expect(find.text('缓存写入 800'), findsOneWidget, reason: '$width');
        expect(find.text('输出 0'), findsOneWidget, reason: '$width');
        expect(find.textContaining('推理'), findsNothing, reason: '$width');
        expect(tester.takeException(), isNull, reason: '$width');
      }
    });

    testWidgets('流式中或无已知用量时不显示', (tester) async {
      await _pumpBubble(
        tester,
        _assistantMessage(
          isStreaming: true,
          tokenUsage: const ChatGenerationUsage(inputTokens: 1),
        ),
      );
      expect(find.text('输入 1'), findsNothing);

      await _pumpBubble(tester, _assistantMessage());
      expect(find.textContaining('缓存命中'), findsNothing);
    });
  });
}
