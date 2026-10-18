import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/protocols/anthropic/anthropic_parser.dart';

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
  });

  // ── 流结束与 ping ─────────────────────────────────────────────

  group('流结束与 ping', () {
    test('message_stop → isDone', () {
      final result = newParser().parse(event('{"type":"message_stop"}'));
      expect(result.isDone, isTrue);
      expect(result.chunk, isNull);
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
          isA<LlmException>()
              .having((e) => e.message, 'message', 'Overloaded')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'overloaded_error')
              .having((e) => e.protocol, 'protocol', protocol)
              .having((e) => e.uri, 'uri', uri),
        ),
      );
    });
  });

  group('工具内容块明确失败', () {
    test('合法 tool_use 起始块只记录调用而不执行', () {
      final parser = newParser();
      final result = parser.parse(
        event(
          '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"a","name":"read","input":{}}}',
        ),
      );
      expect(result.chunk, isNull);
      expect(parser.hasToolCalls, isTrue);
      expect(() => parser.finishToolCalls(), throwsA(isA<LlmException>()));
    });

    test('content_block_start + server_tool_use → 不支持异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use"}}',
          ),
        ),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            contains('不支持该响应类型'),
          ),
        ),
      );
    });

    test('所有工具或未知 content_block_start 类型均明确失败', () {
      for (final blockType in ['server_tool_use', 'future_tool_block']) {
        expect(
          () => newParser().parse(
            event(
              '{"type":"content_block_start","content_block":{"type":"$blockType"}}',
            ),
          ),
          throwsA(
            isA<LlmException>().having(
              (error) => error.message,
              'message',
              contains('不支持该响应类型'),
            ),
          ),
          reason: blockType,
        );
      }
    });

    test('content_block_delta + input_json_delta → 不支持异常', () {
      expect(
        () => newParser().parse(
          event(
            '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}',
          ),
        ),
        throwsA(
          isA<LlmException>().having(
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
            isA<LlmException>().having(
              (e) => e.message,
              'message',
              contains('不支持该响应类型'),
            ),
          ),
          reason: type,
        );
      }
    });
  });

  // ── usage ─────────────────────────────────────────────────────

  group('usage 提取', () {
    test('原生 message_start 输入用量与 message_delta 输出用量累计合并', () {
      final parser = newParser();
      final startChunk = parser
          .parse(
            event(
              '{"type":"message_start","message":{"role":"assistant",'
              '"usage":{"input_tokens":10,"cache_creation_input_tokens":4,'
              '"cache_read_input_tokens":3}}}',
            ),
          )
          .chunk;
      expect(
        startChunk!.usage,
        const LlmUsage(
          inputTokens: 17,
          cachedInputTokens: 3,
          cacheWriteInputTokens: 4,
        ),
      );

      final deltaChunk = parser
          .parse(
            event(
              '{"type":"message_delta","usage":{"output_tokens":20},'
              '"delta":{"stop_reason":"end_turn"}}',
            ),
          )
          .chunk;
      expect(
        deltaChunk!.usage,
        const LlmUsage(
          inputTokens: 17,
          outputTokens: 20,
          reasoningTokens: null,
          cachedInputTokens: 3,
          cacheWriteInputTokens: 4,
        ),
      );
      expect(deltaChunk.finishReason, 'stop');
    });
  });

  // ── 格式错误与未知事件 ────────────────────────────────────────

  group('格式错误与未知事件', () {
    test('malformed JSON → 抛 LlmException', () {
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
  });
}
