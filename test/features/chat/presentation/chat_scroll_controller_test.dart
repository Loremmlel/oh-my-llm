import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_scroll_controller.dart';

import '../../../helpers/async/widget_test_animation.dart';

List<ChatMessage> _messages(int count) {
  return [
    for (var index = 0; index < count; index += 1)
      ChatMessage(
        id: 'message-$index',
        role: index.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
        content: '消息 $index',
        createdAt: DateTime(2026, 1, 1).add(Duration(seconds: index)),
      ),
  ];
}

Widget _list(
  ChatScrollController controller,
  ValueNotifier<double> lastHeight,
) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 240,
        child: ValueListenableBuilder<double>(
          valueListenable: lastHeight,
          builder: (context, height, _) {
            return ScrollablePositionedList.builder(
              itemScrollController: controller.itemScrollController,
              itemPositionsListener: controller.itemPositionsListener,
              itemCount: 12,
              itemBuilder: (context, index) => SizedBox(
                height: index == 11 ? height : 48,
                child: Text('消息 $index'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('同一会话内容增长不自动追底，手动到底仍对齐消息末尾', (tester) async {
    final controller = ChatScrollController();
    final lastHeight = ValueNotifier<double>(48);
    addTearDown(controller.dispose);
    addTearDown(lastHeight.dispose);
    final messages = _messages(12);
    controller.cacheVisibleMessageMetadata(messages, const []);

    await tester.pumpWidget(_list(controller, lastHeight));
    controller.scheduleConversationScroll(
      conversationId: 'c1',
      lastMessageId: messages.last.id,
    );
    await tester.pump();
    await tester.pump();
    controller.handleVisibleItemsChanged();
    expect(controller.showScrollToBottom, isFalse);

    final leadingBeforeGrowth = controller
        .itemPositionsListener
        .itemPositions
        .value
        .firstWhere((position) => position.index == 11)
        .itemLeadingEdge;
    lastHeight.value = 720;
    controller.scheduleConversationScroll(
      conversationId: 'c1',
      lastMessageId: messages.last.id,
    );
    await tester.pump();
    controller.handleVisibleItemsChanged();

    final grownPosition = controller.itemPositionsListener.itemPositions.value
        .firstWhere((position) => position.index == 11);
    expect(grownPosition.itemLeadingEdge, closeTo(leadingBeforeGrowth, 0.01));
    expect(controller.showScrollToBottom, isTrue);

    final scrollFuture = controller.scrollToBottom();
    await settleScrollMotion(tester);
    await scrollFuture;
    controller.handleVisibleItemsChanged();
    final bottomPosition = controller.itemPositionsListener.itemPositions.value
        .firstWhere((position) => position.index == 11);
    expect(bottomPosition.itemTrailingEdge, closeTo(1, 0.02));
    expect(controller.showScrollToBottom, isFalse);
  });

  testWidgets('打开或切换会话时一次性定位到最后一条消息', (tester) async {
    final controller = ChatScrollController();
    final lastHeight = ValueNotifier<double>(48);
    addTearDown(controller.dispose);
    addTearDown(lastHeight.dispose);
    final messages = _messages(12);
    controller.cacheVisibleMessageMetadata(messages, const []);

    await tester.pumpWidget(_list(controller, lastHeight));
    controller.scheduleConversationScroll(
      conversationId: 'c1',
      lastMessageId: messages.last.id,
    );
    await tester.pump();
    await tester.pump();
    expect(
      controller.itemPositionsListener.itemPositions.value.any(
        (position) => position.index == 11,
      ),
      isTrue,
    );

    controller.itemScrollController.jumpTo(index: 0);
    await tester.pump();
    controller.scheduleConversationScroll(
      conversationId: 'c2',
      lastMessageId: messages.last.id,
    );
    await tester.pump();
    await tester.pump();
    expect(
      controller.itemPositionsListener.itemPositions.value.any(
        (position) => position.index == 11,
      ),
      isTrue,
    );
  });

  testWidgets('离开底部后基础会话尾节点变化不自动滚动', (tester) async {
    final controller = ChatScrollController();
    final lastHeight = ValueNotifier<double>(48);
    addTearDown(controller.dispose);
    addTearDown(lastHeight.dispose);
    final messages = _messages(12);
    controller.cacheVisibleMessageMetadata(messages, const []);

    await tester.pumpWidget(_list(controller, lastHeight));
    controller.scheduleConversationScroll(
      conversationId: 'c1',
      lastMessageId: messages.last.id,
    );
    await tester.pump();
    await tester.pump();

    controller.itemScrollController.jumpTo(index: 0);
    await tester.pump();
    controller.handleVisibleItemsChanged();
    expect(controller.showScrollToBottom, isTrue);

    controller.scheduleConversationScroll(
      conversationId: 'c1',
      lastMessageId: 'new-tail',
    );
    await tester.pump();
    await tester.pump();

    expect(
      controller.itemPositionsListener.itemPositions.value.any(
        (position) => position.index == 0,
      ),
      isTrue,
    );
    expect(controller.showScrollToBottom, isTrue);
  });
}
