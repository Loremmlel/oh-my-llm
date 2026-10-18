import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/navigation/message_anchor_rail.dart';

ChatMessage _userMessage({
  required String id,
  String content = 'message content',
}) {
  return ChatMessage(
    id: id,
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime.now(),
    parentId: 'root',
  );
}

/// 直接挂载锚点组件，不装配应用依赖。
///
/// [onSelectMessage] 缺省时自动提供空回调。
Future<void> pumpAnchorRail(
  WidgetTester tester, {
  required List<ChatMessage> userMessages,
  String? activeMessageId,
  ValueChanged<String>? onSelectMessage,
  double maxHeight = 400,
}) async {
  return tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: MessageAnchorRail(
          userMessages: userMessages,
          activeMessageId: activeMessageId,
          maxHeight: maxHeight,
          onSelectMessage: onSelectMessage ?? (_) {},
        ),
      ),
    ),
  );
}

/// 定位第 1 条锚点条目的语义节点（label 格式 `第 1 条用户消息：<preview>`）。
///
/// hover/longPress 直接施加在语义节点上即可命中 rail 的展开交互区域，
/// 不再依赖容器级 test-key。
Finder _firstAnchor(String preview) =>
    find.bySemanticsLabel('第 1 条用户消息：$preview');

/// 当前持有主焦点的语义节点。
/// 带尾部 TextField sentinel 的锚点挂载：焦点离开 rail 后落在 sentinel，
/// 不会 wrap 回第一个锚点，保证「焦点完全离开后折叠」可验证。
Future<void> _pumpRailWithSentinel(
  WidgetTester tester, {
  required List<ChatMessage> userMessages,
  String? activeMessageId,
  ValueChanged<String>? onSelectMessage,
  double maxHeight = 400,
}) async {
  // 锚点交互控件与 TextField 都需要 Material 祖先，MaterialApp 的 home 不会
  // 自动提供（pumpAnchorRail 里已有的 Material 包裹同理）。
  return tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Column(
          children: [
            const SizedBox(height: 40),
            MessageAnchorRail(
              userMessages: userMessages,
              activeMessageId: activeMessageId,
              maxHeight: maxHeight,
              onSelectMessage: onSelectMessage ?? (_) {},
            ),
            const TextField(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  // ── 容器级展开: 悬停交互 ──────────────────────────────────

  group('MessageAnchorRail container hover', () {
    testWidgets('鼠标进入时展开预览，离开后折叠', (tester) async {
      final messages = List.generate(
        5,
        (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
      );
      await pumpAnchorRail(tester, userMessages: messages);

      expect(find.text('消息1'), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(_firstAnchor('消息1')));
      await tester.pumpAndSettle();

      expect(find.text('消息1'), findsOneWidget);

      await gesture.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();

      expect(find.text('消息1'), findsNothing);

      await gesture.removePointer();
    });
  });

  // ── 容器级展开: 长按交互与守卫 ────────────────────────────
  group('a11y 语义与焦点契约', () {
    List<ChatMessage> fiveMessages() => [
      for (var i = 1; i <= 5; i++)
        _userMessage(id: 'msg-$i', content: '第 $i 条消息内容'),
    ];

    testWidgets('键盘进入 rail 展开，按顺序激活 msg-1、msg-2', (tester) async {
      final selected = <String>[];
      await _pumpRailWithSentinel(
        tester,
        userMessages: fiveMessages(),
        onSelectMessage: selected.add,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // 焦点进入 rail 后预览展开，视觉 preview 出现
      expect(find.text('第 1 条消息内容'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-1']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['msg-1', 'msg-2']);
    });
  });
}
