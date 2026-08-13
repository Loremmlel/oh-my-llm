import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_parser.dart';

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

    test(
      'malformed JSON → 抛 ChatGenerationException（携带 protocol/uri/body）',
      () {
        expect(
          () => newParser().parse(event('{not valid json}')),
          throwsA(
            isA<ChatGenerationException>()
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
      },
    );

    test('非 Map JSON（List）→ 无 chunk', () {
      final result = newParser().parse(event('[1, 2, 3]'));
      expect(result.chunk, isNull);
      expect(result.isDone, isFalse);
    });

    test('error 为非空 String → 抛异常，message 为错误文本', () {
      expect(
        () => newParser().parse(event('{"error":"invalid api key"}')),
        throwsA(
          isA<ChatGenerationException>()
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
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'rate limited')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'rate_limit'),
        ),
      );
    });

    test('error 为空值 → 忽略并返回无 chunk', () {
      final emptyString = newParser().parse(event('{"error":"  "}'));
      expect(emptyString.chunk, isNull);
      expect(emptyString.isDone, isFalse);

      final emptyMap = newParser().parse(event('{"error":{}}'));
      expect(emptyMap.chunk, isNull);
    });

    test('无 choices 字段 → 无 chunk', () {
      final result = newParser().parse(event('{"model":"gpt-4.1"}'));
      expect(result.chunk, isNull);
    });

    test('choices 为空数组或首元素非 Map → 无 chunk', () {
      final emptyList = newParser().parse(event('{"choices":[]}'));
      expect(emptyList.chunk, isNull);

      final notMap = newParser().parse(event('{"choices":["x"]}'));
      expect(notMap.chunk, isNull);
    });
  });

  // ── delta 提取 ─────────────────────────────────────────────────

  group('delta 提取', () {
    test('delta.content String → contentDelta', () {
      final chunk = newParser()
          .parse(event('{"choices":[{"delta":{"content":"hello"}}]}'))
          .chunk;
      expect(chunk, isNotNull);
      expect(chunk!.contentDelta, 'hello');
      expect(chunk.reasoningDelta, isEmpty);
    });

    test('delta.reasoning_content → reasoningDelta', () {
      final chunk = newParser()
          .parse(event('{"choices":[{"delta":{"reasoning_content":"思考中"}}]}'))
          .chunk;
      expect(chunk!.reasoningDelta, '思考中');
      expect(chunk.contentDelta, isEmpty);
    });

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

    test('content 内联标签 → 标签剔除、内部文本入 reasoningDelta', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"content":"前缀<think>隐藏</think>后缀"}}]}',
            ),
          )
          .chunk;
      expect(chunk!.contentDelta, '前缀后缀');
      expect(chunk.reasoningDelta, '隐藏');
    });

    test('reasoning_content 与内联标签并存 → 先显式后内联', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"content":"A<think>内联</think>B","reasoning_content":"显式"}}]}',
            ),
          )
          .chunk;
      expect(chunk!.contentDelta, 'AB');
      expect(chunk.reasoningDelta, '显式内联');
    });

    test('内联标签跨事件保持状态（同一 parser 实例）', () {
      final parser = newParser();
      final first = parser.parse(
        event('{"choices":[{"delta":{"content":"A<think"}}]}'),
      );
      expect(first.chunk!.contentDelta, 'A');
      expect(first.chunk!.reasoningDelta, isEmpty);

      final second = parser.parse(
        event('{"choices":[{"delta":{"content":"ing>R1</thinking>B"}}]}'),
      );
      expect(second.chunk!.contentDelta, 'B');
      expect(second.chunk!.reasoningDelta, 'R1');
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

    test('finish_reason 缺失或非 String → null', () {
      final missing = newParser()
          .parse(event('{"choices":[{"delta":{"content":"hi"}}]}'))
          .chunk;
      expect(missing!.finishReason, isNull);

      final notString = newParser()
          .parse(
            event('{"choices":[{"delta":{"content":"hi"},"finish_reason":1}]}'),
          )
          .chunk;
      expect(notString!.finishReason, isNull);
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

    test('delta.content 为 List → 按无内容处理，不提取文本', () {
      final chunk = newParser()
          .parse(
            event(
              '{"choices":[{"delta":{"content":[{"text":"segment1"},{"text":"segment2"}]}}]}',
            ),
          )
          .chunk;
      expect(chunk, isNotNull);
      expect(chunk!.contentDelta, isEmpty);
      expect(chunk.reasoningDelta, isEmpty);
    });

    test('delta.reasoning 别名 → 不进入 reasoningDelta', () {
      final chunk = newParser()
          .parse(event('{"choices":[{"delta":{"reasoning":"别名推理"}}]}'))
          .chunk;
      expect(chunk, isNotNull);
      expect(chunk!.reasoningDelta, isEmpty);
      expect(chunk.contentDelta, isEmpty);
    });

    test('delta 缺失或非 Map → 仅保留 finishReason', () {
      final missing = newParser()
          .parse(event('{"choices":[{"finish_reason":"stop"}]}'))
          .chunk;
      expect(missing!.finishReason, 'stop');
      expect(missing.contentDelta, isEmpty);

      final stringDelta = newParser()
          .parse(event('{"choices":[{"delta":"纯文本"}]}'))
          .chunk;
      expect(stringDelta, isNotNull);
      expect(stringDelta!.contentDelta, isEmpty);
    });
  });

  // ── usage ──────────────────────────────────────────────────────

  group('usage 提取', () {
    test('顶层 usage 自然携带时映射为 ChatGenerationUsage', () {
      final chunk = newParser()
          .parse(
            event(
              '{"usage":{"prompt_tokens":10,"completion_tokens":20,'
              '"completion_tokens_details":{"reasoning_tokens":5},'
              '"prompt_tokens_details":{"cached_tokens":3}},'
              '"choices":[{"delta":{"content":"hi"}}]}',
            ),
          )
          .chunk;
      expect(
        chunk!.usage,
        const ChatGenerationUsage(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 3,
        ),
      );
    });

    test('usage 缺失或全非 int → usage 为 null', () {
      final missing = newParser()
          .parse(event('{"choices":[{"delta":{"content":"hi"}}]}'))
          .chunk;
      expect(missing!.usage, isNull);

      final notInt = newParser()
          .parse(
            event(
              '{"usage":{"prompt_tokens":"x","completion_tokens":null},'
              '"choices":[{"delta":{"content":"hi"}}]}',
            ),
          )
          .chunk;
      expect(notInt!.usage, isNull);
    });
  });

  // ── finish ─────────────────────────────────────────────────────

  group('finish() 尾部刷新', () {
    test('不完整开标签残留 → 按 content 通道输出', () {
      final parser = newParser();
      parser.parse(event('{"choices":[{"delta":{"content":"正文<未闭合"}}]}'));
      final remainder = parser.finish();
      expect(remainder, isNotNull);
      expect(remainder!.contentDelta, '<未闭合');
      expect(remainder.reasoningDelta, isEmpty);
    });

    test('reasoning 状态残留 → 按 reasoning 通道输出', () {
      final parser = newParser();
      parser.parse(
        event('{"choices":[{"delta":{"content":"<think>推理内容<未闭"}}]}'),
      );
      final remainder = parser.finish();
      expect(remainder, isNotNull);
      expect(remainder!.reasoningDelta, '<未闭');
      expect(remainder.contentDelta, isEmpty);
    });

    test('无残留 → null', () {
      final parser = newParser();
      parser.parse(event('{"choices":[{"delta":{"content":"完整正文"}}]}'));
      expect(parser.finish(), isNull);
    });
  });
}
