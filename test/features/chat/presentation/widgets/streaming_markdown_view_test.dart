import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/streaming_markdown_view.dart';

Finder _findRichTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is RichText) {
      return widget.text.toPlainText().contains(text);
    }
    return false;
  }, description: 'RichText containing "$text"');
}

void main() {
  group('normalizeLatexLikeTextForDisplay', () {
    test('只替换已知箭头命令，并保留未知命令与普通文本', () {
      expect(
        normalizeLatexLikeTextForDisplay(
          r'方向：$\LeftArrow$、$\RightArrow$、$\LeftRightArrow$',
        ),
        '方向：←、→、↔',
      );
      expect(
        normalizeLatexLikeTextForDisplay(r'未知：$\UnknownSymbol$'),
        r'未知：$\UnknownSymbol$',
      );
      expect(normalizeLatexLikeTextForDisplay('普通文本 123'), '普通文本 123');
    });
  });

  group('StreamingMarkdownView smooth streaming', () {
    testWidgets('流式时即时回显最新增量并在结束后保留最终内容', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownView(content: '', isStreaming: true),
          ),
        ),
      );

      expect(find.text('正在等待模型返回内容...'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownView(content: '第一段', isStreaming: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('第一段'), findsWidgets);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownView(content: '第一段\n第二段', isStreaming: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在等待模型返回内容...'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownView(
              content: '第一段\n第二段',
              isStreaming: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_findRichTextContaining('第一段'), findsOneWidget);
      expect(_findRichTextContaining('第二段'), findsOneWidget);
      expect(find.text('正在等待模型返回内容...'), findsNothing);
    });
  });
}
