import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';

import '../../../../../../helpers/fixtures.dart';

void main() {
  testWidgets('长用户消息先提供展开入口，再提供整条消息操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatMessageBubble(
              message: TestFixtures.userMessage(
                id: 'long-user',
                content: '${'正文\n' * 24}最后一行',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('最后一行'), findsNothing);
    final controls = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.label)
        .where((label) => label == '展开全文' || label.contains('复制'));
    expect(controls.first, '展开全文');
    await tester.ensureVisible(find.text('展开全文'));
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(find.text('收起内容'), findsOneWidget);
    expect(find.textContaining('最后一行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
