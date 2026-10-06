import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/dialogs/rename_conversation_dialog.dart';

import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('重命名按手机键盘完成后返回去除空白的标题', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      const RenameConversationDialog(initialTitle: '旧标题'),
                );
              },
              child: const Text('打开重命名'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开重命名'));
    await settleOverlayTransition(tester);
    await tester.enterText(find.widgetWithText(TextField, '会话标题'), '  新标题  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleOverlayTransition(tester);
    expect(result, '新标题');
    expect(find.text('打开重命名'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
  });
}
