import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../helpers/async/widget_test_animation.dart';
import '../../../../../helpers/test_harness.dart';

void main() {
  testWidgets('短屏上下文过滤可滚动浏览且关闭按钮可达', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpTestApp(
      tester,
      preferences: await SharedPreferences.getInstance(),
      viewportSize: const Size(390, 360),
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const MessageRequestFilterDialog(),
          ),
          child: const Text('打开过滤'),
        ),
      ),
    );
    await tester.tap(find.text('打开过滤'));
    await settleOverlayTransition(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(find.text('当前分支还没有消息。').first, const Offset(0, -120));
    await settleScrollMotion(tester);
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    expect(find.text('上下文过滤'), findsNothing);
  });
}
