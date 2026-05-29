import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/chat_scroll_controller.dart';

void main() {
  group('ChatScrollController', () {
    test(
      'onScroll callback fires when handleVisibleItemsChanged'
      ' triggers a state change',
      () {
        var callbackCalled = false;
        final controller = ChatScrollController(
          onStateChange: () {},
          isMounted: () => true,
          onScroll: () {
            callbackCalled = true;
          },
        );

        // 初始状态 showScrollToBottom = false，预先设为 true
        // 这样 handleVisibleItemsChanged 会检测到变化（true → false），
        // 进入有状态更新分支，触发 onScroll 回调。
        controller.showScrollToBottom = true;

        controller.handleVisibleItemsChanged();

        expect(callbackCalled, isTrue);
        expect(controller.showScrollToBottom, isFalse);
      },
    );

    test(
      'handleVisibleItemsChanged works without onScroll callback'
      ' (no crash)',
      () {
        final controller = ChatScrollController(
          onStateChange: () {},
          isMounted: () => true,
        );

        controller.showScrollToBottom = true;

        expect(
          () => controller.handleVisibleItemsChanged(),
          returnsNormally,
        );
      },
    );
  });
}
