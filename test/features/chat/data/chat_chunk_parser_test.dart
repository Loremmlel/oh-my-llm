import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/chat_chunk_parser.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────────

  const parser = ChatChunkParser();

  /// 解析单个 raw chunk，省去手写 splitter 的样板。
  ChatCompletionChunk? parse(
    String raw, {
    InlineReasoningTagSplitter? splitter,
  }) {
    return parser.parseRawChunk(
      raw,
      inlineReasoningSplitter: splitter ?? InlineReasoningTagSplitter(),
    );
  }

  // ── ChatChunkParser.parseRawChunk ────────────────────────────

  group('ChatChunkParser.parseRawChunk', () {
    test('[DONE] 返回 null', () {
      expect(parse('[DONE]'), isNull);
    });

    test('非 JSON 字符串抛 ChatCompletionException', () {
      expect(
        () => parse('{not valid json}'),
        throwsA(isA<ChatCompletionException>()),
      );
    });

    test('非 Map（如 List）返回 empty chunk', () {
      final result = parse('[1, 2, 3]');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('非 Map（如字符串）返回 empty chunk', () {
      final result = parse('"hello"');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('error 为非空 String → 抛异常含该 message', () {
      expect(
        () => parse('{"error": "invalid api key"}'),
        throwsA(
          isA<ChatCompletionException>().having(
            (e) => e.message,
            'message',
            'invalid api key',
          ),
        ),
      );
    });

    test('error 为含 message 的 Map → 抛异常含该 message', () {
      expect(
        () => parse('{"error": {"message": "rate limit exceeded"}}'),
        throwsA(
          isA<ChatCompletionException>().having(
            (e) => e.message,
            'message',
            'rate limit exceeded',
          ),
        ),
      );
    });

    test('error 为空 Map → 不抛异常，返回 empty chunk', () {
      final result = parse('{"error": {}}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('error 为空 String → 不抛异常，返回 empty chunk', () {
      final result = parse('{"error": "  "}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('choices 为空数组 → empty chunk', () {
      final result = parse('{"choices": []}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('choices 首元素非 Map → empty chunk', () {
      final result = parse('{"choices": ["not-a-map"]}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('无 choices 字段 → empty chunk', () {
      final result = parse('{"model": "gpt-4"}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('标准 OpenAI delta.content 字符串 → contentDelta', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hello"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.contentDelta, 'hello');
      expect(result.reasoningDelta, isEmpty);
    });

    test('DeepSeek delta.reasoning_content → reasoningDelta', () {
      final result = parse(
        '{"choices":[{"delta":{"reasoning_content":"思考中"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.reasoningDelta, '思考中');
      expect(result.contentDelta, isEmpty);
    });

    test('DeepSeek delta.reasoning 别名 → reasoningDelta', () {
      final result = parse(
        '{"choices":[{"delta":{"reasoning":"别名推理"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.reasoningDelta, '别名推理');
    });

    test('DeepSeek content + reasoning_content 同时存在', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"正文","reasoning_content":"推理"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.contentDelta, '正文');
      expect(result.reasoningDelta, '推理');
    });

    test('Gemini content 为带 thought 的 parts 列表 → 拆分 content/reasoning',
        () {
      final result = parse(
        '{"choices":[{"delta":{"content":['
        '{"text":"最终答案"},'
        '{"text":"思考摘要","thought":true}'
        ']}}]}',
      );
      expect(result, isNotNull);
      expect(result!.contentDelta, '最终答案');
      expect(result.reasoningDelta, '思考摘要');
    });

    test('Gemini thought 字段为字符串 "true" 也视为思考内容', () {
      final result = parse(
        '{"choices":[{"delta":{"content":['
        '{"text":"隐藏推理","thought":"true"}'
        ']}}]}',
      );
      expect(result, isNotNull);
      expect(result!.reasoningDelta, '隐藏推理');
    });

    test('delta 为 String 类型 → 经 inline splitter 处理', () {
      final result = parse(
        '{"choices":[{"delta":"纯文本 delta"}]}',
      );
      expect(result, isNotNull);
      expect(result!.contentDelta, '纯文本 delta');
    });

    test('delta 为 null → empty chunk', () {
      final result = parse('{"choices":[{"delta":null}]}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('使用 message 而非 delta 字段（一次性响应）也能提取', () {
      final result = parse(
        '{"choices":[{"message":{"content":"完整回复"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.contentDelta, '完整回复');
    });

    test('choices[0].finish_reason 为 "stop" → chunk.finishReason 为 "stop"', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}]}',
      );
      expect(result, isNotNull);
      expect(result!.finishReason, 'stop');
      expect(result!.contentDelta, 'hi');
    });

    test('finish_reason 为 null 时 chunk.finishReason 为 null', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}',
      );
      expect(result, isNotNull);
      expect(result!.finishReason, isNull);
    });

    test('无 finish_reason 字段时 chunk.finishReason 为 null', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hi"}}]}',
      );
      expect(result, isNotNull);
      expect(result!.finishReason, isNull);
    });

    test('finish_reason 为 "length" → chunk.finishReason 为 "length"', () {
      final result = parse(
        '{"choices":[{"delta":{},"finish_reason":"length"}]}',
      );
      expect(result, isNotNull);
      expect(result!.finishReason, 'length');
      expect(result!.isEmpty, isTrue);
    });
  });

  // ── InlineReasoningTagSplitter ────────────────────────────────

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

    test('完整 <thought>...</thought> 标签内容进入 reasoning 通道', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('前文<thought>隐藏推理</thought>后文');
      expect(result.content, '前文后文');
      expect(result.reasoning, '隐藏推理');
    });

    test('大小写不敏感：<THOUGHTS> 与 <thinkings> 均识别', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        'A<THOUGHTS>R1</THOUGHTS>B<thinkings>R2</thinkings>C',
      );
      expect(result.content, 'ABC');
      expect(result.reasoning, 'R1R2');
    });

    test('跨 chunk 的开标签拼接：<think + ing>R1</thinking> 仍能识别', () {
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

    test('标签外的普通 < 字符原样输出到 content', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent('a < b && c > d');
      expect(result.content, 'a < b && c > d');
      expect(result.reasoning, isEmpty);
    });

    test('标签内外的文本正确分流到对应通道', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        '<thought>推理内容</thought>正文内容',
      );
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

    test('连续多个 thought 标签都能正确分离', () {
      final splitter = InlineReasoningTagSplitter();
      final result = splitter.splitContent(
        '<thought>R1</thought>C1<thought>R2</thought>C2',
      );
      expect(result.content, 'C1C2');
      expect(result.reasoning, 'R1R2');
    });
  });
}
