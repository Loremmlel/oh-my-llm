import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/reasoning_panel.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/streaming_markdown_view.dart';

import '../../../../../../helpers/async/stream_markdown_test_animation.dart';

/// 当前持有主焦点的语义节点。
SemanticsFinder _focusedNode() =>
    find.semantics.byFlag(SemanticsFlag.isFocused);

Widget _wrap(String content, {bool isStreaming = false}) {
  return MaterialApp(
    home: Scaffold(
      body: ReasoningPanel(content: content, isStreaming: isStreaming),
    ),
  );
}

void main() {
  group('ReasoningPanel 语义', () {
    testWidgets('初始 header 恰好一个「深度思考」节点，expanded=false', (tester) async {
      await tester.pumpWidget(_wrap('# 标题\n推理内容'));

      final header = find.semantics.byLabel('深度思考');
      expect(header, findsOneWidget);
      expect(
        header,
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hint: '激活以展开',
        ),
      );
      // 可见「展开」文本不产生第二个语义节点
      expect(find.semantics.byLabel('展开'), findsNothing);
      expect(find.byType(StreamingMarkdownView), findsNothing);
    });

    testWidgets('展开后流式推理连续更新，收起时销毁 Markdown 子树', (tester) async {
      await tester.pumpWidget(_wrap('第一段', isStreaming: true));
      await tester.tap(find.text('深度思考'));
      await tester.pump();
      await pumpStreamMarkdownRefresh(tester);

      expect(find.byType(StreamingMarkdownView), findsOneWidget);
      expect(find.text('第一段'), findsOneWidget);

      await tester.pumpWidget(_wrap('第一段第二段', isStreaming: true));
      await pumpStreamMarkdownRefresh(tester);
      expect(find.text('第一段第二段'), findsOneWidget);

      await tester.tap(find.text('深度思考'));
      await tester.pump();
      expect(find.byType(StreamingMarkdownView), findsNothing);
    });

    testWidgets('激活后 expanded=true，Markdown 内容在语义树可读，再激活收回', (tester) async {
      await tester.pumpWidget(_wrap('# 标题\n推理内容'));

      tester.semantics.tap(find.semantics.byLabel('深度思考'));
      await tester.pump();

      final header = find.semantics.byLabel('深度思考');
      expect(
        header,
        isSemantics(hasExpandedState: true, isExpanded: true, hint: '激活以收起'),
      );
      // findsWidgets：Markdown 渲染器可能把内容拆成多个语义节点，
      // 只要求内容可读，不承诺恰好一个节点
      expect(
        find.semantics.byPredicate((n) => n.label.contains('推理内容')),
        findsWidgets,
      );

      tester.semantics.tap(header);
      await tester.pump();

      expect(
        find.semantics.byLabel('深度思考'),
        isSemantics(isExpanded: false, hint: '激活以展开'),
      );
      expect(
        find.semantics.byPredicate((n) => n.label.contains('推理内容')),
        findsNothing,
      );
    });

    testWidgets('Tab 聚焦 header 后 Enter 切换，header 保持焦点', (tester) async {
      await tester.pumpWidget(_wrap('推理内容'));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedNode(), isSemantics(label: '深度思考'));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(_focusedNode(), isSemantics(label: '深度思考'));
      expect(
        find.semantics.byLabel('深度思考'),
        isSemantics(isExpanded: true, isFocused: true),
      );
    });
  });
}
