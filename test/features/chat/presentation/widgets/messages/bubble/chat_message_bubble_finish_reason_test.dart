import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';

ChatMessage _assistantMessage({
  String content = '正文',
  String? finishReason,
  bool isStreaming = false,
  LlmUsage? tokenUsage,
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
  group('结束原因', () {
    testWidgets('正常停止不显示标记，异常结束原因原位可见', (tester) async {
      await _pumpBubble(tester, _assistantMessage(finishReason: 'stop'));
      expect(find.text('stop'), findsNothing);

      await _pumpBubble(
        tester,
        _assistantMessage(finishReason: 'length', isStreaming: true),
      );
      expect(find.text('length'), findsNothing);

      await _pumpBubble(tester, _assistantMessage(finishReason: 'length'));
      expect(find.text('length'), findsOneWidget);
    });
  });

  group('Token 用量', () {
    testWidgets('服务商未报告 Token 时仍显示首字时间', (tester) async {
      await _pumpBubble(
        tester,
        _assistantMessage(
          tokenUsage: const LlmUsage(
            timeToFirstToken: Duration(milliseconds: 750),
          ),
        ),
        width: 320,
      );
      expect(find.text('TPS —'), findsOneWidget);
      expect(find.text('· 首字 0.75 s'), findsOneWidget);
    });

    testWidgets('终态助手消息按固定顺序显示已知值并保留显式 0', (tester) async {
      for (final width in [320.0, 800.0]) {
        await _pumpBubble(
          tester,
          _assistantMessage(
            tokenUsage: const LlmUsage(
              inputTokens: 4000,
              cachedInputTokens: 1500,
              cacheWriteInputTokens: 800,
              outputTokens: 0,
              outputDuration: Duration(seconds: 2),
              timeToFirstToken: Duration(milliseconds: 1250),
            ),
          ),
          width: width,
        );

        expect(find.text('输入 4,000'), findsOneWidget, reason: '$width');
        expect(find.text('· 缓存命中 1,500'), findsOneWidget, reason: '$width');
        expect(find.text('· 缓存写入 800'), findsOneWidget, reason: '$width');
        expect(find.text('· 输出 0'), findsOneWidget, reason: '$width');
        expect(find.text('· TPS 0.0'), findsOneWidget, reason: '$width');
        expect(find.text('· 首字 1.25 s'), findsOneWidget, reason: '$width');
        expect(find.textContaining('推理'), findsNothing, reason: '$width');
        expect(tester.takeException(), isNull, reason: '$width');
      }
    });

    testWidgets('流式中或无已知用量时不显示', (tester) async {
      await _pumpBubble(
        tester,
        _assistantMessage(
          isStreaming: true,
          tokenUsage: const LlmUsage(inputTokens: 1),
        ),
      );
      expect(find.text('输入 1'), findsNothing);

      for (final usage in <LlmUsage?>[
        null,
        const LlmUsage(reasoningTokens: 8),
      ]) {
        await _pumpBubble(tester, _assistantMessage(tokenUsage: usage));
        expect(find.textContaining('输入 '), findsNothing);
        expect(find.textContaining('输出 '), findsNothing);
        expect(find.textContaining('缓存命中'), findsNothing);
        expect(find.textContaining('缓存写入'), findsNothing);
        expect(find.textContaining('推理'), findsNothing);
        expect(find.text('正文'), findsOneWidget);
      }
    });
  });
}
