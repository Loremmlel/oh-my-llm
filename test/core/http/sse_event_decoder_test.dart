import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';

void main() {
  const decoder = SseEventDecoder();

  test('单个完整事件：data 与 rawData 分离', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data: {"a":1}\n\n')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, '{"a":1}');
    expect(events.single.rawData, 'data: {"a":1}');
    expect(events.single.eventName, isNull);
  });

  test('任意 byte 切分下事件流保持一致（含 UTF-8 跨 chunk）', () async {
    const payload =
        'data: {"content":"中文文本"}\n\n'
        'event: ping\n'
        'data: {"type":"ping"}\n\n'
        'data: 最后\n\n';

    final expected = await decoder
        .decode(Stream.value(utf8.encode(payload)))
        .toList();
    expect(expected, hasLength(3));

    // 逐字节喂入，覆盖任意切分与 UTF-8 多字节序列跨 chunk。
    final controller = StreamController<List<int>>();
    final eventsFuture = decoder.decode(controller.stream).toList();
    for (final byte in utf8.encode(payload)) {
      controller.add([byte]);
    }
    await controller.close();
    final events = await eventsFuture;

    expect(events.length, expected.length);
    for (var i = 0; i < events.length; i++) {
      expect(events[i].data, expected[i].data);
      expect(events[i].rawData, expected[i].rawData);
      expect(events[i].eventName, expected[i].eventName);
    }
  });

  test('多个 data 行以换行连接，rawData 保留行首', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data: a\ndata: b\n\n')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, 'a\nb');
    expect(events.single.rawData, 'data: a\ndata: b');
  });

  test('data 值去除行首一个空格', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data:{"a":1}\ndata:  x\n\n')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, '{"a":1}\n x');
  });

  test('event 行保存为事件名，多个 event 行后者覆盖', () async {
    final events = await decoder
        .decode(
          Stream.value(
            utf8.encode('event: first\nevent: ping\ndata: {"t":1}\n\n'),
          ),
        )
        .toList();

    expect(events, hasLength(1));
    expect(events.single.eventName, 'ping');
    expect(events.single.data, '{"t":1}');
  });

  test('事件名不跨事件泄漏', () async {
    final events = await decoder
        .decode(
          Stream.value(
            utf8.encode('event: ping\ndata: {"t":1}\n\ndata: {"t":2}\n\n'),
          ),
        )
        .toList();

    expect(events, hasLength(2));
    expect(events[0].eventName, 'ping');
    expect(events[1].eventName, isNull);
  });

  test('注释行忽略且不产出事件', () async {
    final events = await decoder
        .decode(
          Stream.value(utf8.encode(': keepalive\n: heartbeat\ndata: x\n\n')),
        )
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, 'x');

    final commentsOnly = await decoder
        .decode(Stream.value(utf8.encode(': keepalive\n: heartbeat\n')))
        .toList();
    expect(commentsOnly, isEmpty);
  });

  test('未以空行结束的最后一个事件仍被消费', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data: a\ndata: b')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, 'a\nb');
  });

  test('CRLF 行尾的事件边界', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data: a\r\n\r\ndata: b\r\n\r\n')))
        .toList();

    expect(events, hasLength(2));
    expect(events.map((e) => e.data).toList(), ['a', 'b']);
  });

  test('无 data 行的空事件被丢弃', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('event: ping\n\ndata: x\n\n')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, 'x');
  });

  test('空 data 值事件仍产出（是否消费由协议层决定）', () async {
    final events = await decoder
        .decode(Stream.value(utf8.encode('data:\n\n')))
        .toList();

    expect(events, hasLength(1));
    expect(events.single.data, '');
  });

  testWidgets('注释 keepalive 不重置 idle timeout，超时抛 TimeoutException', (
    tester,
  ) async {
    final source = StreamController<List<int>>();
    final events = <SseEvent>[];
    final errors = <Object>[];
    final subscription = decoder
        .decode(source.stream, idleTimeout: const Duration(seconds: 1))
        .listen(events.add, onError: errors.add);

    source.add(utf8.encode(': keepalive\n: heartbeat\n'));
    await tester.pump();
    expect(events, isEmpty);

    await tester.pump(const Duration(seconds: 2));

    expect(events, isEmpty);
    expect(errors, hasLength(1));
    expect(errors.single, isA<TimeoutException>());
    expect((errors.single as TimeoutException).message, contains('data'));

    unawaited(subscription.cancel());
    unawaited(source.close());
    await tester.pump();
  });

  testWidgets('data 行重置 idle timeout，重置后计时器仍生效', (tester) async {
    const dataArrivalDelay = Duration(milliseconds: 500);
    const postResetObservationDelay = Duration(milliseconds: 600);
    final source = StreamController<List<int>>();
    final events = <SseEvent>[];
    final errors = <Object>[];
    final subscription = decoder
        .decode(source.stream, idleTimeout: const Duration(seconds: 1))
        .listen(events.add, onError: errors.add);

    // t=0 注释行（不重置）；t=500ms data 行把计时器重置到 t=1.5s。
    source.add(utf8.encode(': keepalive\n'));
    await tester.pump();
    await tester.pump(dataArrivalDelay);

    source.add(utf8.encode('data: x\n\n'));
    await tester.pump();

    // t=1.1s：已越过未重置时的 1s 死线，证明 data 行确实重置了计时器。
    await tester.pump(postResetObservationDelay);
    expect(errors, isEmpty);
    expect(events, hasLength(1));
    expect(events.single.data, 'x');

    // t=2.1s：重置后的 1s 计时器到期。
    await tester.pump(const Duration(seconds: 1));
    expect(errors, hasLength(1));
    expect(errors.single, isA<TimeoutException>());

    unawaited(subscription.cancel());
    unawaited(source.close());
    await tester.pump();
  });

  test('取消订阅立即取消底层 byte stream', () async {
    final source = StreamController<List<int>>();
    final events = <SseEvent>[];
    final subscription = decoder.decode(source.stream).listen(events.add);

    // 等解码器完成对底层流的订阅。
    await Future<void>.delayed(Duration.zero);
    expect(source.hasListener, isTrue);

    await subscription.cancel();
    expect(source.hasListener, isFalse);

    await source.close();
  });

  test('SseEvent 值相等（Equatable）', () {
    const a = SseEvent(eventName: 'ping', data: 'x', rawData: 'data: x');
    const b = SseEvent(eventName: 'ping', data: 'x', rawData: 'data: x');
    const c = SseEvent(eventName: 'ping', data: 'y', rawData: 'data: x');

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
    expect(c == const SseEvent(data: 'x', rawData: 'data: x'), isFalse);
  });

  testWidgets('上游错误后取消 idle timer，不再触发超时', (tester) async {
    final source = StreamController<List<int>>();
    final errors = <Object>[];
    final subscription = decoder
        .decode(source.stream, idleTimeout: const Duration(seconds: 1))
        .listen((_) {}, onError: errors.add);

    // data 行重置计时器到 t=1s。
    source.add(utf8.encode('data: x\n\n'));
    await tester.pump();
    expect(errors, isEmpty);

    // 上游直接报错（模拟网络中断）：错误转发后计时器必须取消。
    source.addError(StateError('connection reset'));
    await tester.pump();
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());

    // 若计时器未取消，t=1s 后还会追加 TimeoutException。
    await tester.pump(const Duration(seconds: 2));
    expect(errors, hasLength(1));

    unawaited(subscription.cancel());
    unawaited(source.close());
    await tester.pump();
  });
}
