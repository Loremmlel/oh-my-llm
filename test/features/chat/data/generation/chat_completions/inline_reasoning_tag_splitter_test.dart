import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/generation/chat_completions/inline_reasoning_tag_splitter.dart';

void main() {
  // ── InlineReasoningTagSplitter ─────────────────────────────────

  group('InlineReasoningTagSplitter', () {
    test('空输入返回空结果', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('');
      expect(result.isEmpty, isTrue);
    });

    test('无标签正文原样进入 content 通道', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('普通正文内容');
      expect(result.content, '普通正文内容');
      expect(result.reasoning, isEmpty);
    });

    test('三种单数标签 <thought>/<thinking>/<think> 均识别', () {
      final cases = {
        'thought': ('<thought>R1</thought>', 'R1'),
        'thinking': ('<thinking>R2</thinking>', 'R2'),
        'think': ('<think>R3</think>', 'R3'),
      };
      for (final entry in cases.entries) {
        final splitter = InlineReasoningTagSplitter();
        final result = splitter.splitContent('A${entry.value.$1}B');
        expect(result.content, 'AB', reason: entry.key);
        expect(result.reasoning, entry.value.$2, reason: entry.key);
      }
    });

    test('标签名大小写不敏感', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        'A<THINK>R1</THINK>B<Thought>C</Thought>D',
      );
      expect(result.content, 'ABD');
      expect(result.reasoning, 'R1C');
    });

    test('opening tag 允许空白与属性', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        'A< thinking type="reasoning" lang="zh">R1</thinking>B< thought >R2</thought>C',
      );
      expect(result.content, 'ABC');
      expect(result.reasoning, 'R1R2');
    });

    test('closing tag 允许空白', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('A<think>R1</ think >B');
      expect(result.content, 'AB');
      expect(result.reasoning, 'R1');
    });

    test('复数 <thoughts>/<thinkings> 为普通正文，不触发解析', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        'A<THOUGHTS>R1</THOUGHTS>B<thinkings>R2</thinkings>C',
      );
      expect(
        result.content,
        'A<THOUGHTS>R1</THOUGHTS>B<thinkings>R2</thinkings>C',
      );
      expect(result.reasoning, isEmpty);
    });

    test('跨 chunk 的开标签拼接仍能识别', () {
      final splitter = InlineReasoningTagSplitter();
      final first = splitter.splitContent('A<think');
      // 第一段：标签不完整，进入 _tail，正文 A 已输出
      expect(first.content, 'A');
      expect(first.reasoning, isEmpty);

      final second = splitter.splitContent('ing>R1</thinking>B');
      expect(second.content, 'B');
      expect(second.reasoning, 'R1');
    });

    test('跨 chunk 的闭标签拼接也能识别', () {
      final splitter = InlineReasoningTagSplitter();
      // 先进入 reasoning 模式
      splitter.splitContent('<thought>R1');
      // 闭标签被拆分
      final second = splitter.splitContent('更多推理</tho');
      expect(second.reasoning, '更多推理');

      final third = splitter.splitContent('ught>正文');
      expect(third.content, '正文');
      expect(third.reasoning, isEmpty);
    });

    test('未闭合 opening tag 后内容持续进入 reasoning 通道', () {
      final splitter = InlineReasoningTagSplitter();
      final first = splitter.splitContent('前文<think>推理一');
      expect(first.content, '前文');
      expect(first.reasoning, '推理一');

      final second = splitter.splitContent('推理二');
      expect(second.content, isEmpty);
      expect(second.reasoning, '推理二');
    });

    test('未配对的 closing tag 按普通正文处理', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('前文</thinking>后文');
      expect(result.content, '前文</thinking>后文');
      expect(result.reasoning, isEmpty);
    });

    test('标签外的普通 < 字符原样输出到 content', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('a < b && c > d');
      expect(result.content, 'a < b && c > d');
      expect(result.reasoning, isEmpty);
    });

    test('标签内外的文本正确分流到对应通道', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('<thought>推理内容</thought>正文内容');
      expect(result.content, '正文内容');
      expect(result.reasoning, '推理内容');
      expect(splitter.flushRemainder(), isNull);
    });

    test('不完整开标签残留时 flushRemainder 输出到 content 通道', () {
      final splitter = InlineReasoningTagSplitter();
      splitter.splitContent('正文<未闭合');
      final remainder = splitter.flushRemainder();
      expect(remainder, isNotNull);
      expect(remainder!.contentDelta, '<未闭合');
      expect(remainder.reasoningDelta, isEmpty);
    });

    test('处于 reasoning 状态时的残留 flushRemainder 输出到 reasoning 通道', () {
      final splitter = InlineReasoningTagSplitter();
      splitter.splitContent('<thought>推理内容<未闭');
      final remainder = splitter.flushRemainder();
      expect(remainder, isNotNull);
      expect(remainder!.reasoningDelta, '<未闭');
      expect(remainder.contentDelta, isEmpty);
    });

    test('无残留时 flushRemainder 返回 null', () {
      final splitter = InlineReasoningTagSplitter();
      splitter.splitContent('完整正文');
      expect(splitter.flushRemainder(), isNull);
    });

    test('连续多个标签都能正确分离', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        '<thought>R1</thought>C1<thinking>R2</thinking>C2<think>R3</think>C3',
      );
      expect(result.content, 'C1C2C3');
      expect(result.reasoning, 'R1R2R3');
    });
  });
}
