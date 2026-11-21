import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/streaming_markdown_view.dart';

import '../../../../../../helpers/async/stream_markdown_test_animation.dart';

Widget _wrap(String content, {bool isStreaming = true}) {
  return MaterialApp(
    home: Scaffold(
      body: StreamingMarkdownView(content: content, isStreaming: isStreaming),
    ),
  );
}

void main() {
  testWidgets('Markdown 折叠块在应用主题下可展开', (tester) async {
    await tester.pumpWidget(
      _wrap(
        '<details>\n<summary>展开详情</summary>\n\n说明正文\n\n</details>',
        isStreaming: false,
      ),
    );

    expect(find.text('说明正文'), findsNothing);
    await tester.tap(find.text('展开详情'));
    await tester.pumpAndSettle();
    expect(find.text('说明正文'), findsOneWidget);
  });

  testWidgets('流式正文仅由 Markdown 渲染一次，不附加普通文本尾巴', (tester) async {
    await tester.pumpWidget(_wrap('第一段'));
    await pumpStreamMarkdownRefresh(tester);
    expect(find.text('第一段'), findsOneWidget);

    await tester.pumpWidget(_wrap('第一段第二段'));
    await pumpStreamMarkdownRefresh(tester);

    expect(find.text('第一段第二段'), findsOneWidget);
    expect(find.text('第二段'), findsNothing);
  });

  testWidgets('Android 长按框选 Markdown 正文时选择菜单正常弹出且不抛异常', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(_wrap('这是一段用于验证长按框选的助手回复正文', isStreaming: false));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('这是一段用于验证长按框选的助手回复正文'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
  });
}
