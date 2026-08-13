import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/responses/responses_parser.dart';

void main() {
  const protocol = LlmApiProtocol.responses;
  final uri = Uri.parse('https://api.example.com/v1/responses');

  /// 构造解析器（默认每用例一个实例，状态不跨用例共享）。
  ResponsesParser newParser() => ResponsesParser(protocol: protocol, uri: uri);

  /// 从 data 文本构造 SSE 事件（rawData 带 data: 前缀）。
  SseEvent event(String data) => SseEvent(data: data, rawData: 'data: $data');

  // ── 文本四通道 ────────────────────────────────────────────────

  group('文本增量', () {
    test('response.output_text.delta → contentDelta', () {
      final result = newParser().parse(
        event('{"type":"response.output_text.delta","delta":"你好"}'),
      );
      expect(result.recognized, isTrue);
      expect(result.chunk!.contentDelta, '你好');
      expect(result.chunk!.reasoningDelta, isEmpty);
    });

    test('response.reasoning_summary_text.delta → reasoningDelta', () {
      final result = newParser().parse(
        event('{"type":"response.reasoning_summary_text.delta","delta":"摘要"}'),
      );
      expect(result.chunk!.reasoningDelta, '摘要');
      expect(result.chunk!.contentDelta, isEmpty);
    });

    test('response.reasoning_text.delta → reasoningDelta', () {
      final result = newParser().parse(
        event('{"type":"response.reasoning_text.delta","delta":"详细推理"}'),
      );
      expect(result.chunk!.reasoningDelta, '详细推理');
      expect(result.chunk!.contentDelta, isEmpty);
    });

    test('response.refusal.delta → 用户可见 contentDelta', () {
      final result = newParser().parse(
        event('{"type":"response.refusal.delta","delta":"抱歉，我无法回答"}'),
      );
      expect(result.chunk!.contentDelta, '抱歉，我无法回答');
      expect(result.chunk!.reasoningDelta, isEmpty);
    });

    test('delta 缺失或非 String → 空增量', () {
      final missing = newParser().parse(
        event('{"type":"response.output_text.delta"}'),
      );
      expect(missing.chunk!.contentDelta, isEmpty);

      final notString = newParser().parse(
        event('{"type":"response.reasoning_text.delta","delta":123}'),
      );
      expect(notString.chunk!.reasoningDelta, isEmpty);
    });
  });

  // ── finish reason 归一化 ──────────────────────────────────────

  group('finish reason 归一化', () {
    test('response.completed → finishReason stop', () {
      final result = newParser().parse(event('{"type":"response.completed"}'));
      expect(result.recognized, isTrue);
      expect(result.isDone, isTrue);
      expect(result.chunk!.finishReason, 'stop');
    });

    test('response.incomplete + max_output_tokens → length', () {
      final result = newParser().parse(
        event(
          '{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}',
        ),
      );
      expect(result.chunk!.finishReason, 'length');
      expect(result.isDone, isTrue);
    });

    test('response.incomplete 其他 reason → 保留原值', () {
      final result = newParser().parse(
        event(
          '{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}',
        ),
      );
      expect(result.chunk!.finishReason, 'content_filter');
    });

    test('response.incomplete 缺 reason → 以 incomplete 兜底归一化为 length', () {
      final missingDetails = newParser().parse(
        event('{"type":"response.incomplete"}'),
      );
      expect(missingDetails.chunk!.finishReason, 'length');

      final emptyReason = newParser().parse(
        event(
          '{"type":"response.incomplete","response":{"incomplete_details":{"reason":"  "}}}',
        ),
      );
      expect(emptyReason.chunk!.finishReason, 'length');
    });
  });

  // ── 错误事件 ──────────────────────────────────────────────────

  group('错误事件', () {
    test('error 事件 → 提取顶层 message/code 抛异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"error","message":"invalid api key","code":"invalid_api_key"}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'invalid_api_key')
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri),
        ),
      );
    });

    test('response.failed → 从 response.error 提取 message/code 抛异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"response.failed","response":{"error":{"code":"server_error","message":"Server had an error"}}}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'Server had an error')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'server_error')
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri),
        ),
      );
    });

    test('response.failed 无 error 详情 → 抛默认文案异常', () {
      expect(
        () => newParser().parse(event('{"type":"response.failed"}')),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('响应生成失败'),
          ),
        ),
      );
    });
  });

  // ── response.done ─────────────────────────────────────────────

  group('response.done', () {
    test('只做完整性检查，不追加其中完整文本', () {
      final parser = newParser();
      parser.parse(
        event('{"type":"response.output_text.delta","delta":"第一段 "}'),
      );
      parser.parse(
        event('{"type":"response.output_text.delta","delta":"第二段"}'),
      );

      final done = parser.parse(
        event(
          '{"type":"response.done","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"第一段 第二段"}]}]}}',
        ),
      );
      expect(done.chunk, isNull);
      expect(done.isDone, isTrue);
      expect(done.recognized, isTrue);
    });

    test('缺少 response envelope → 抛异常', () {
      expect(
        () => newParser().parse(event('{"type":"response.done"}')),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('response.done'),
          ),
        ),
      );
    });
  });

  group('内容项 done 事件', () {
    test('完整文本或推理只做校验，不重复追加增量', () {
      for (final data in [
        '{"type":"response.output_text.done","text":"完整正文"}',
        '{"type":"response.reasoning_summary_text.done","text":"完整推理"}',
        '{"type":"response.refusal.done","refusal":"完整拒绝"}',
        '{"type":"response.content_part.done","part":{"type":"output_text","text":"完整正文"}}',
        '{"type":"response.output_item.done","item":{"type":"message"}}',
      ]) {
        final result = newParser().parse(event(data));
        expect(result.chunk, isNull, reason: data);
        expect(result.isDone, isFalse, reason: data);
        expect(result.recognized, isTrue, reason: data);
      }
    });
  });

  // ── usage ─────────────────────────────────────────────────────

  group('usage 提取', () {
    test('response.usage 自然携带时映射为 ChatGenerationUsage', () {
      final chunk = newParser()
          .parse(
            event(
              '{"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":20,'
              '"output_tokens_details":{"reasoning_tokens":5},'
              '"input_tokens_details":{"cached_tokens":3}}}}',
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
          .parse(event('{"type":"response.completed"}'))
          .chunk;
      expect(missing!.usage, isNull);

      final notInt = newParser()
          .parse(
            event(
              '{"type":"response.incomplete","response":{"usage":{"input_tokens":"x","output_tokens":null}}}',
            ),
          )
          .chunk;
      expect(notInt!.usage, isNull);
    });
  });

  // ── 格式错误与未知事件 ────────────────────────────────────────

  group('格式错误与未知事件', () {
    test('malformed JSON → 抛 ChatGenerationException', () {
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
    });

    test('非 Map JSON（List）→ 忽略', () {
      final result = newParser().parse(event('[1, 2, 3]'));
      expect(result.chunk, isNull);
      expect(result.isDone, isFalse);
      expect(result.recognized, isFalse);
    });

    test('无 type 字段 → 忽略', () {
      final result = newParser().parse(event('{"model":"gpt-5"}'));
      expect(result.chunk, isNull);
      expect(result.recognized, isFalse);
    });

    test('未知/生命周期事件类型 → 忽略（不产生 chunk）', () {
      for (final type in [
        'response.created',
        'response.in_progress',
        'response.output_item.added',
      ]) {
        final result = newParser().parse(event('{"type":"$type"}'));
        expect(result.chunk, isNull, reason: type);
        expect(result.isDone, isFalse, reason: type);
        expect(result.recognized, isFalse, reason: type);
      }
    });
  });
}
