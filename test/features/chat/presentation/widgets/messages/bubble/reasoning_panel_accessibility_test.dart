import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/reasoning_panel.dart';

import '../../../../../../helpers/async/stream_markdown_test_animation.dart';

Widget _wrap(String content, {bool isStreaming = false}) {
  return MaterialApp(
    home: Scaffold(
      body: ReasoningPanel(content: content, isStreaming: isStreaming),
    ),
  );
}

void main() {
  group('ReasoningPanel 语义', () {
    testWidgets('展开后流式推理连续更新，收起后内容不可见', (tester) async {
      await tester.pumpWidget(_wrap('第一段', isStreaming: true));
      await tester.tap(find.text('深度思考'));
      await tester.pump();
      await pumpStreamMarkdownRefresh(tester);

      expect(find.text('第一段'), findsOneWidget);

      await tester.pumpWidget(_wrap('第一段第二段', isStreaming: true));
      await pumpStreamMarkdownRefresh(tester);
      expect(find.text('第一段第二段'), findsOneWidget);
      expect(find.text('· 6 字'), findsOneWidget);

      await tester.pumpWidget(_wrap('hello world', isStreaming: true));
      await pumpStreamMarkdownRefresh(tester);
      expect(find.text('· 2 字'), findsOneWidget);

      await tester.tap(find.text('深度思考'));
      await tester.pump();
      expect(find.text('hello world'), findsNothing);
    });
  });
}
