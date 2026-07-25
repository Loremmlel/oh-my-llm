import 'dart:async';

import 'app_log_store.dart';

/// SSE 日志有界缓冲区。
///
/// 固定容量，溢出时丢弃最旧条目并写入 `[sse-dropped]` 标记。
/// 定时（每 [flushInterval] 或满 [batchSize] 条）批量 flush 到 [AppLogStore]。
/// [drain] 用于生命周期结束前排空所有缓冲条目。
final class SseLogBuffer {
  SseLogBuffer({
    required this.store,
    this.maxCapacity = 128,
    this.batchSize = 64,
    this.flushInterval = const Duration(milliseconds: 500),
  });

  final AppLogStore store;
  final int maxCapacity;
  final int batchSize;
  final Duration flushInterval;

  final List<String> _buffer = [];
  int _droppedCount = 0;
  Timer? _flushTimer;
  bool _isDrained = false;

  /// 启动定时 flush。
  void startPeriodicFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) {
      // 忽略 flush 返回的 Future——定时器回调不应用 await 阻塞
      flush();
    });
  }

  /// 入队一条 SSE 日志行。
  ///
  /// O(1) 操作，不阻塞 SSE 流。容量满时丢弃最旧条目。
  void enqueue(String line) {
    if (_isDrained) return;
    if (_buffer.length >= maxCapacity) {
      _buffer.removeAt(0);
      _droppedCount++;
    }
    _buffer.add(line);

    // 满 batchSize 时自动 flush
    if (_buffer.length >= batchSize) {
      flush();
    }
  }

  /// 批量 flush 缓冲区内容到 [AppLogStore]。
  ///
  /// 若有丢弃的条目，先写入 `[sse-dropped]` 标记。
  Future<void> flush() async {
    if (_buffer.isEmpty && _droppedCount == 0) return;

    final lines = <String>[];
    if (_droppedCount > 0) {
      final now = DateTime.now().toIso8601String();
      lines.add('[$now] [sse-dropped] $_droppedCount lines dropped');
      _droppedCount = 0;
    }
    lines.addAll(_buffer);
    _buffer.clear();

    await store.appendLines(lines);
  }

  /// 排空缓冲区并停止定时器。
  ///
  /// 用于应用退出前确保 SSE buffer 排空。调用后 [enqueue] 不再接受新条目。
  Future<void> drain() async {
    _isDrained = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
  }
}
