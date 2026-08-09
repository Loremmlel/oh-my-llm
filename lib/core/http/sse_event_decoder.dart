import 'dart:async';
import 'dart:convert';

/// SSE 解码事件。
///
/// [data] 为多个 `data:` 行按换行连接后的值；[rawData] 保留原始 data 行
/// 文本（含 `data:` 前缀），供日志与错误诊断。
class SseEvent {
  const SseEvent({this.eventName, required this.data, required this.rawData});

  /// `event:` 字段值；事件未声明事件名时为 null。
  final String? eventName;

  /// 多个 `data:` 行以换行连接后的字符串（每行去除行首一个空格）。
  final String data;

  /// 原始 data 行文本（含 `data:` 前缀），以换行连接。
  final String rawData;
}

/// SSE 事件解码器：把网络 byte chunk 流解码为事件流。
///
/// 契约：
/// - 空行结束事件；多个 `data:` 行以换行连接；`event:` 保存为事件名；
///   `:` 注释行忽略。
/// - 未以空行结束的最后一个事件在流结束时仍被消费。
/// - 仅 `data:` 行重置 idle timeout（注释 keepalive 不重置），超时以
///   [TimeoutException] 作为流错误抛出。
/// - 取消订阅立即取消底层 byte stream。
///
/// 本类不解析任何协议 JSON，不知道 `[DONE]` 等协议标记。
class SseEventDecoder {
  const SseEventDecoder();

  Stream<SseEvent> decode(
    Stream<List<int>> byteStream, {
    Duration? idleTimeout,
  }) {
    // UTF-8 多字节序列跨 chunk 时由 utf8.decoder 内部缓冲拼接。
    final lineStream = byteStream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    late StreamController<SseEvent> controller;
    late StreamSubscription<String> lineSubscription;
    Timer? idleTimer;

    String? eventName;
    final dataLines = <String>[];
    final rawDataLines = <String>[];

    void fireTimeout() {
      if (controller.isClosed) {
        return;
      }
      controller.addError(
        TimeoutException(
          'SSE 流在 ${idleTimeout!.inSeconds} 秒内没有新 data 行',
          idleTimeout,
        ),
      );
      unawaited(lineSubscription.cancel());
      controller.close();
    }

    void resetTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout!, fireTimeout);
    }

    void flushEvent() {
      if (dataLines.isEmpty) {
        // 事件没有任何 data 行（纯 event:/注释行）直接丢弃。
        eventName = null;
        return;
      }
      controller.add(
        SseEvent(
          eventName: eventName,
          data: dataLines.join('\n'),
          rawData: rawDataLines.join('\n'),
        ),
      );
      eventName = null;
      dataLines.clear();
      rawDataLines.clear();
    }

    void handleLine(String line) {
      if (controller.isClosed) {
        return;
      }
      if (line.isEmpty) {
        // 空行结束当前事件。
        flushEvent();
        return;
      }
      if (line.startsWith(':')) {
        // 注释行：忽略，且不重置 idle timeout。
        return;
      }
      if (line.startsWith('data:')) {
        dataLines.add(_stripLeadingSpace(line.substring('data:'.length)));
        rawDataLines.add(line);
        if (idleTimeout != null) {
          // 只有 data: 行代表服务器产出了有效内容，重置超时计时器。
          resetTimer();
        }
        return;
      }
      if (line.startsWith('event:')) {
        // 多个 event: 行按规范后者覆盖前者。
        eventName = _stripLeadingSpace(line.substring('event:'.length));
      }
      // 其他 SSE 字段（id / retry / 未知字段）忽略。
    }

    controller = StreamController<SseEvent>(
      onListen: () {
        lineSubscription = lineStream.listen(
          handleLine,
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
          onDone: () {
            idleTimer?.cancel();
            if (controller.isClosed) {
              return;
            }
            // 尾部无空行的事件仍被消费。
            flushEvent();
            controller.close();
          },
          cancelOnError: false,
        );
        if (idleTimeout != null) {
          resetTimer();
        }
      },
      onPause: () => lineSubscription.pause(),
      onResume: () => lineSubscription.resume(),
      onCancel: () {
        idleTimer?.cancel();
        return lineSubscription.cancel();
      },
    );

    return controller.stream;
  }

  /// 去除 field value 行首一个空格（SSE 规范）。
  static String _stripLeadingSpace(String value) {
    if (value.startsWith(' ')) {
      return value.substring(1);
    }
    return value;
  }
}
