import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/app_log_store.dart';
import 'package:oh_my_llm/core/logging/sse_log_buffer.dart';

void main() {
  late AppLogStore store;
  late Directory tempDir;
  late String logFilePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sse-buffer-test-');
    logFilePath = '${tempDir.path}${Platform.pathSeparator}network.log';
    store = await AppLogStore.open(
      directoryPath: tempDir.path,
      maxBytes: 1024 * 1024,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SseLogBuffer', () {
    test('flush 写入磁盘且无在途写入时幂等', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 10, batchSize: 5);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      await buffer.flush();
      await buffer.flush();

      final content = await File(logFilePath).readAsString();
      expect(content, contains('line-1'));
      expect(content, contains('line-2'));
    });

    test('容量满时丢弃最旧条目并记录数量', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 3, batchSize: 10);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      buffer.enqueue('line-3');
      buffer.enqueue('line-4'); // 溢出，line-1 被丢弃
      await buffer.drain();

      final content = await File(logFilePath).readAsString();
      expect(content, contains('line-2'));
      expect(content, contains('line-3'));
      expect(content, contains('line-4'));
      expect(content, isNot(contains('line-1')));
      expect(content, contains('[sse-dropped] 1 lines dropped'));
    });

    test('drain 排空所有条目', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 10, batchSize: 10);

      buffer.enqueue('line-A');
      buffer.enqueue('line-B');
      await buffer.drain();

      // drain 后入队应被忽略
      buffer.enqueue('line-C');

      final content = await File(logFilePath).readAsString();
      expect(content, contains('line-A'));
      expect(content, contains('line-B'));
      expect(content, isNot(contains('line-C')));
    });
  });

  test('达到阈值后的立即 flush 等待已在途的自动写入', () async {
    final buffer = SseLogBuffer(
      store: store,
      batchSize: 2,
      flushInterval: const Duration(days: 1),
    );
    addTearDown(buffer.drain);
    buffer.enqueue('第一行');
    buffer.enqueue('第二行'); // 达到阈值，自动 flush 已在途
    await buffer.flush(); // 空 buffer 但存在在途写入，必须等待其完成
    final content = await File(logFilePath).readAsString();
    expect(content, contains('第一行'));
    expect(content, contains('第二行'));
  });
}
