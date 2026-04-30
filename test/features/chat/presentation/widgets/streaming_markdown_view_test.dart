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
    test('常见箭头命令会降级为可读符号', () {
      final output = normalizeLatexLikeTextForDisplay(
        r'方向：$\LeftArrow$、$\RightArrow$、$\LeftRightArrow$',
      );

      expect(output, '方向：←、→、↔');
    });

    test('未知命令保持原样，避免误改', () {
      final output = normalizeLatexLikeTextForDisplay(r'未知：$\UnknownSymbol$');

      expect(output, r'未知：$\UnknownSymbol$');
    });

    test('非 TeX 文本不受影响', () {
      final output = normalizeLatexLikeTextForDisplay('普通文本 123');
      expect(output, '普通文本 123');
    });
  });

  group('StreamingMarkdownView smooth streaming', () {
    testWidgets('流式时可持续追加渲染并在结束后保留最终内容', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 120));
      expect(_findRichTextContaining('第一段'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownView(content: '第一段\n第二段', isStreaming: true),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_findRichTextContaining('第一段'), findsOneWidget);
      expect(_findRichTextContaining('第二段'), findsOneWidget);

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
      await tester.pump();
      expect(_findRichTextContaining('第一段'), findsOneWidget);
      expect(_findRichTextContaining('第二段'), findsOneWidget);
    });
  });
}
