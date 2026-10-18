import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_parser.dart';

void main() {
  const protocol = LlmApiProtocol.chatCompletions;
  final uri = Uri.parse('https://api.example.com/v1/chat/completions');

  /// 构造解析器（默认每用例一个实例，状态不跨用例共享）。
  ChatCompletionsParser newParser() =>
      ChatCompletionsParser(protocol: protocol, uri: uri);

  /// 从 data 文本构造 SSE 事件（rawData 带 data: 前缀）。
  SseEvent event(String data) => SseEvent(data: data, rawData: 'data: $data');

  // ── 流结束标记与格式错误 ────────────────────────────────────────

  group('流结束与错误', () {
    test('[DONE] → isDone=true 且无 chunk', () {
      final result = newParser().parse(event('[DONE]'));
      expect(result.isDone, isTrue);
      expect(result.chunk, isNull);
    });

    test('malformed JSON → 抛 LlmException（携带 protocol/uri/body）', () {
      expect(
        () => newParser().parse(event('{not valid json}')),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', contains('SSE 数据解析失败'))
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri)
              .having(
                (e) => e.responseBody,
                'responseBody',
                '{not valid json}',
              ),
        ),
      );
    });

    test('error 为非空 String → 抛异常，message 为错误文本', () {
      expect(
        () => newParser().parse(event('{"error":"invalid api key"}')),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri),
        ),
      );
    });

    test('error 为含 message/code 的 Map → 抛异常并提取 apiErrorCode', () {
      expect(
        () => newParser().parse(
          event('{"error":{"message":"rate limited","code":"rate_limit"}}'),
        ),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', 'rate limited')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'rate_limit'),
        ),
      );
    });
  });

  // ── delta 提取 ─────────────────────────────────────────────────

  group('delta 提取', () {
    test('content 与 reasoning_content 同存 → 各入其通道', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"content":"正文","reasoning_content":"推理"}}]}',
            ),
          )
          .chunk;
      expect(chunk!.contentDelta, '正文');
      expect(chunk.reasoningDelta, '推理');
    });

    test('共享解析器保留内联标签原文', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"content":"A<think>内联</think>B","reasoning_content":"显式"}}]}',
            ),
          )
          .chunk!;
      expect(chunk.contentDelta, 'A<think>内联</think>B');
      expect(chunk.reasoningDelta, '显式');
    });

    test('finish_reason 原样透传（stop/length/非常规值）', () {
      for (final raw in ['stop', 'length', 'tool_calls']) {
        final chunk = newParser()
            .parse(
              event(
                '{"choices":[{"delta":{"content":"hi"},"finish_reason":"$raw"}]}',
              ),
            )
            .chunk;
        expect(chunk!.finishReason, raw, reason: raw);
      }
    });

    test('message envelope（一次性响应形状）同样提取', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"message":{"content":"完整回复","reasoning_content":"完整思考"},"finish_reason":"stop"}]}',
            ),
          )
          .chunk;
      expect(chunk!.contentDelta, '完整回复');
      expect(chunk.reasoningDelta, '完整思考');
      expect(chunk.finishReason, 'stop');
    });

    test('delta.reasoning → reasoningDelta', () {
      final chunk = newParser()
          .parse(event('{"choices":[{"delta":{"reasoning":"别名推理"}}]}'))
          .chunk;
      expect(chunk, isNotNull);
      expect(chunk!.reasoningDelta, '别名推理');
      expect(chunk.contentDelta, isEmpty);
    });

    test('两个推理字段同存时优先 reasoning_content', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"reasoning_content":"规范推理","reasoning":"别名推理"}}]}',
            ),
          )
          .chunk;
      expect(chunk!.reasoningDelta, '规范推理');
    });
  });

  // ── usage ──────────────────────────────────────────────────────

  group('usage 提取', () {
    test('顶层 usage 自然携带时映射为 LlmUsage', () {
      final chunk = newParser()
          .parse(
            event(
              '{"usage":{"prompt_tokens":10,"completion_tokens":20,'
              '"completion_tokens_details":{"reasoning_tokens":5},'
              '"prompt_tokens_details":{"cached_tokens":3,"cache_write_tokens":0}},'
              '"choices":[{"delta":{"content":"hi"}}]}',
            ),
          )
          .chunk;
      expect(
        chunk!.usage,
        const LlmUsage(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 3,
          cacheWriteInputTokens: 0,
        ),
      );
    });

    test('空 choices 的流尾事件仍输出 usage', () {
      final chunk = newParser()
          .parse(
            event(
              '{"usage":{"prompt_tokens":10,"completion_tokens":2},"choices":[]}',
            ),
          )
          .chunk;

      expect(chunk!.usage, const LlmUsage(inputTokens: 10, outputTokens: 2));
      expect(chunk.isEmpty, isTrue);
    });
  });

  // ── finish ─────────────────────────────────────────────────────
}
