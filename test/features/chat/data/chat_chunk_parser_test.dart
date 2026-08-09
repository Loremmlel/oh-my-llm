import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/chat_chunk_parser.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────────

  const parser = ChatChunkParser();

  /// 解析单个 raw chunk，省去手写 splitter 的样板。
  ChatGenerationChunk? parse(
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

    test('非 JSON 字符串抛 ChatGenerationException', () {
      expect(
        () => parse('{not valid json}'),
        throwsA(isA<ChatGenerationException>()),
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
          isA<ChatGenerationException>().having(
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
          isA<ChatGenerationException>().having(
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
      final result = parse('{"choices":[{"delta":{"content":"hello"}}]}');
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
      final result = parse('{"choices":[{"delta":{"reasoning":"别名推理"}}]}');
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

    test('Gemini content 为带 thought 的 parts 列表 → 拆分 content/reasoning', () {
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
      final result = parse('{"choices":[{"delta":"纯文本 delta"}]}');
      expect(result, isNotNull);
      expect(result!.contentDelta, '纯文本 delta');
    });

    test('delta 为 null → empty chunk', () {
      final result = parse('{"choices":[{"delta":null}]}');
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    test('使用 message 而非 delta 字段（一次性响应）也能提取', () {
      final result = parse('{"choices":[{"message":{"content":"完整回复"}}]}');
      expect(result, isNotNull);
      expect(result!.contentDelta, '完整回复');
    });

    test('choices[0].finish_reason 为 "stop" → chunk.finishReason 为 "stop"', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}]}',
      );
      expect(result, isNotNull);
      final chunk = result!;
      expect(chunk.finishReason, 'stop');
      expect(chunk.contentDelta, 'hi');
    });

    test('finish_reason 为 null 时 chunk.finishReason 为 null', () {
      final result = parse(
        '{"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}',
      );
      expect(result, isNotNull);
      expect(result!.finishReason, isNull);
    });

    test('无 finish_reason 字段时 chunk.finishReason 为 null', () {
      final result = parse('{"choices":[{"delta":{"content":"hi"}}]}');
      expect(result, isNotNull);
      expect(result!.finishReason, isNull);
    });

    test('finish_reason 为 "length" → chunk.finishReason 为 "length"', () {
      final result = parse(
        '{"choices":[{"delta":{},"finish_reason":"length"}]}',
      );
      expect(result, isNotNull);
      final chunk = result!;
      expect(chunk.finishReason, 'length');
      expect(chunk.isEmpty, isTrue);
    });
  });
}
