import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/streaming_markdown_view.dart';

import '../../../../../../helpers/async/stream_markdown_test_animation.dart';

Widget _wrap(String content) {
  return MaterialApp(
    home: Scaffold(
      body: StreamingMarkdownView(content: content, isStreaming: true),
    ),
  );
}

void main() {
  testWidgets('流式正文仅由 Markdown 渲染一次，不附加普通文本尾巴', (tester) async {
    await tester.pumpWidget(_wrap('第一段'));
    await pumpStreamMarkdownRefresh(tester);
    expect(find.text('第一段'), findsOneWidget);

    await tester.pumpWidget(_wrap('第一段第二段'));
    await pumpStreamMarkdownRefresh(tester);

    expect(find.text('第一段第二段'), findsOneWidget);
    expect(find.text('第二段'), findsNothing);
  });
}
