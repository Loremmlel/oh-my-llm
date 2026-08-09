import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/anthropic/anthropic_parser.dart';

void main() {
  const protocol = LlmApiProtocol.anthropic;
  final uri = Uri.parse('https://api.example.com/v1/messages');

  /// 构造解析器（默认每用例一个实例，状态不跨用例共享）。
  AnthropicParser newParser() => AnthropicParser(protocol: protocol, uri: uri);

  /// 从 data 文本构造 SSE 事件（rawData 带 data: 前缀）。
  SseEvent event(String data) => SseEvent(data: data, rawData: 'data: $data');

  // ── 文本与推理增量 ─────────────────────────────────────────────

  group('内容块增量', () {
    test('content_block_delta + text_delta → contentDelta', () {
      final result = newParser().parse(
        event(
          '{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}',
        ),
      );
      expect(result.recognized, isTrue);
      expect(result.chunk!.contentDelta, '你好');
      expect(result.chunk!.reasoningDelta, isEmpty);
    });

    test('content_block_delta + thinking_delta → reasoningDelta', () {
      final result = newParser().parse(
        event(
          '{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"思考中"}}',
        ),
      );
      expect(result.chunk!.reasoningDelta, '思考中');
      expect(result.chunk!.contentDelta, isEmpty);
    });

    test('content_block_delta + signature_delta → 忽略', () {
      final result = newParser().parse(
        event(
          '{"type":"content_block_delta","delta":{"type":"signature_delta","signature":"sig"}}',
        ),
      );
      expect(result.chunk, isNull);
      expect(result.isDone, isFalse);
      expect(result.recognized, isTrue);
    });

    test('text/thinking 字段缺失或非 String → 空增量', () {
      final missingText = newParser().parse(
        event('{"type":"content_block_delta","delta":{"type":"text_delta"}}'),
      );
      expect(missingText.chunk!.contentDelta, isEmpty);

      final notString = newParser().parse(
        event(
          '{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":123}}',
        ),
      );
      expect(notString.chunk!.reasoningDelta, isEmpty);
    });

    test('content_block_start / content_block_stop / message_start → 忽略', () {
      final start = newParser().parse(
        event(
          '{"type":"content_block_start","content_block":{"type":"text","text":""}}',
        ),
      );
      expect(start.chunk, isNull);
      expect(start.recognized, isTrue);

      final stop = newParser().parse(
        event('{"type":"content_block_stop","index":0}'),
      );
      expect(stop.chunk, isNull);
      expect(stop.recognized, isTrue);

      final messageStart = newParser().parse(
        event('{"type":"message_start","message":{"role":"assistant"}}'),
      );
      expect(messageStart.chunk, isNull);
      expect(messageStart.recognized, isTrue);
    });
  });

  // ── finish reason 归一化 ──────────────────────────────────────

  group('finish reason 归一化', () {
    test('end_turn / stop_sequence → stop', () {
      for (final raw in ['end_turn', 'stop_sequence']) {
        final result = newParser().parse(
          event('{"type":"message_delta","delta":{"stop_reason":"$raw"}}'),
        );
        expect(result.chunk!.finishReason, 'stop', reason: raw);
      }
    });

    test('max_tokens / model_context_window_exceeded → length', () {
      for (final raw in ['max_tokens', 'model_context_window_exceeded']) {
        final result = newParser().parse(
          event('{"type":"message_delta","delta":{"stop_reason":"$raw"}}'),
        );
        expect(result.chunk!.finishReason, 'length', reason: raw);
      }
    });

    test('refusal → refusal', () {
      final result = newParser().parse(
        event('{"type":"message_delta","delta":{"stop_reason":"refusal"}}'),
      );
      expect(result.chunk!.finishReason, 'refusal');
    });

    test('其他 stop_reason 保留原值', () {
      final result = newParser().parse(
        event('{"type":"message_delta","delta":{"stop_reason":"pause_turn"}}'),
      );
      expect(result.chunk!.finishReason, 'pause_turn');
    });

    test('message_delta 无 stop_reason 也无 usage → 忽略', () {
      final result = newParser().parse(
        event('{"type":"message_delta","delta":{"stop_sequence":"zzz"}}'),
      );
      expect(result.chunk, isNull);
      expect(result.recognized, isTrue);
    });
  });

  // ── 流结束与 ping ─────────────────────────────────────────────

  group('流结束与 ping', () {
    test('message_stop → isDone', () {
      final result = newParser().parse(event('{"type":"message_stop"}'));
      expect(result.isDone, isTrue);
      expect(result.chunk, isNull);
      expect(result.recognized, isTrue);
    });

    test('ping → 忽略（data 行仍由 transport 层重置 idle timeout）', () {
      final result = newParser().parse(event('{"type":"ping"}'));
      expect(result.chunk, isNull);
      expect(result.isDone, isFalse);
      expect(result.recognized, isTrue);
    });
  });

  // ── 错误与不支持的事件 ─────────────────────────────────────────

  group('错误事件', () {
    test('error 事件 → 从 error.type/error.message 提取 code/message', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'Overloaded')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'overloaded_error')
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri),
        ),
      );
    });

    test('error 事件无 error envelope → 抛默认文案异常', () {
      expect(
        () => newParser().parse(event('{"type":"error"}')),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('error'),
          ),
        ),
      );
    });
  });

  group('工具内容块明确失败', () {
    test('content_block_start + tool_use → 不支持异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t-1","name":"f","input":{}}}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('不支持该响应类型'),
          ),
        ),
      );
    });

    test('content_block_start + server_tool_use → 不支持异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use"}}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('不支持该响应类型'),
          ),
        ),
      );
    });

    test('content_block_delta + input_json_delta → 不支持异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}',
          ),
        ),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.message,
            'message',
            contains('不支持该响应类型'),
          ),
        ),
      );
    });

    test('未知事件名按 _ 分词命中 tool/failed/incomplete → 不得按未知忽略', () {
      for (final type in ['tool_use', 'run_failed', 'run_incomplete']) {
        expect(
          () => newParser().parse(event('{"type":"$type"}')),
          throwsA(
            isA<ChatGenerationException>().having(
              (e) => e.message,
              'message',
              contains('不支持该响应类型'),
            ),
          ),
          reason: type,
        );
      }
    });

    test('tooltip_ready 前缀近似 → 不再误触发，按未知事件忽略', () {
      final result = newParser().parse(event('{"type":"tooltip_ready"}'));
      expect(result.chunk, isNull);
      expect(result.isDone, isFalse);
      expect(result.recognized, isFalse);
    });
  });

  // ── usage ─────────────────────────────────────────────────────

  group('usage 提取', () {
    test('message_delta usage 自然携带时填充', () {
      final chunk = newParser()
          .parse(
            event(
              '{"type":"message_delta","usage":{"input_tokens":10,"output_tokens":20,'
              '"cache_creation_input_tokens":4,"cache_read_input_tokens":3},'
              '"delta":{"stop_reason":"end_turn"}}',
            ),
          )
          .chunk;
      expect(
        chunk!.usage,
        const ChatGenerationUsage(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: null,
          cachedInputTokens: 3,
        ),
      );
    });

    test('usage 缺失或全非 int → usage 为 null', () {
      final missing = newParser()
          .parse(
            event(
              '{"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
            ),
          )
          .chunk;
      expect(missing!.usage, isNull);
      expect(missing.finishReason, 'stop');

      final notInt = newParser()
          .parse(
            event(
              '{"type":"message_delta","usage":{"input_tokens":"x","output_tokens":null},'
              '"delta":{"stop_reason":"end_turn"}}',
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
      final result = newParser().parse(event('{"model":"claude-4"}'));
      expect(result.chunk, isNull);
      expect(result.recognized, isFalse);
    });

    test('未知事件类型 → 忽略（不产生 chunk）', () {
      for (final type in [
        'message.start',
        'content_block.budget',
        'future.unknown_event',
      ]) {
        final result = newParser().parse(event('{"type":"$type"}'));
        expect(result.chunk, isNull, reason: type);
        expect(result.isDone, isFalse, reason: type);
        expect(result.recognized, isFalse, reason: type);
      }
    });

    test('未知 delta 类型 → 忽略', () {
      final result = newParser().parse(
        event(
          '{"type":"content_block_delta","delta":{"type":"future_delta","x":1}}',
        ),
      );
      expect(result.chunk, isNull);
      expect(result.recognized, isFalse);
    });
  });
}
