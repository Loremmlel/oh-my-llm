import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/app_log_store.dart';
import 'package:oh_my_llm/core/logging/sse_log_buffer.dart';

void main() {
  late AppLogStore store;
  late String tempDir;

  setUp(() async {
    tempDir =
        '${Directory.systemTemp.path}${Platform.pathSeparator}sse_buffer_test_${DateTime.now().millisecondsSinceEpoch}';
    store = await AppLogStore.open(
      directoryPath: tempDir,
      maxBytes: 1024 * 1024,
    );
  });

  tearDown(() async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('SseLogBuffer', () {
    test('正常入队 + flush 写入磁盘', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 10, batchSize: 5);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      await buffer.flush();

      final content = await File(
        '${tempDir}${Platform.pathSeparator}network.log',
      ).readAsString();
      expect(content, contains('line-1'));
      expect(content, contains('line-2'));
    });

    test('容量满时丢弃最旧条目', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 3, batchSize: 10);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      buffer.enqueue('line-3');
      buffer.enqueue('line-4'); // 溢出，line-1 被丢弃
      await buffer.drain();

      final content = await File(
        '${tempDir}${Platform.pathSeparator}network.log',
      ).readAsString();
      expect(content, contains('line-2'));
      expect(content, contains('line-3'));
      expect(content, contains('line-4'));
      expect(content, isNot(contains('line-1')));
    });

    test('丢弃时写 [sse-dropped] 标记', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 2, batchSize: 10);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      buffer.enqueue('line-3'); // 丢弃 line-1
      buffer.enqueue('line-4'); // 丢弃 line-2
      await buffer.drain();

      final content = await File(
        '${tempDir}${Platform.pathSeparator}network.log',
      ).readAsString();
      expect(content, contains('[sse-dropped] 2 lines dropped'));
    });

    test('drain 排空所有条目', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 10, batchSize: 10);

      buffer.enqueue('line-A');
      buffer.enqueue('line-B');
      await buffer.drain();

      // drain 后入队应被忽略
      buffer.enqueue('line-C');

      final content = await File(
        '${tempDir}${Platform.pathSeparator}network.log',
      ).readAsString();
      expect(content, contains('line-A'));
      expect(content, contains('line-B'));
      expect(content, isNot(contains('line-C')));
    });

    test('满 batchSize 时自动 flush', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 20, batchSize: 3);

      buffer.enqueue('line-1');
      buffer.enqueue('line-2');
      buffer.enqueue('line-3'); // 满 batchSize，触发自动 flush

      // 给异步 flush 一点时间
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final content = await File(
        '${tempDir}${Platform.pathSeparator}network.log',
      ).readAsString();
      expect(content, contains('line-1'));
      expect(content, contains('line-3'));

      await buffer.drain();
    });

    test('空 flush 不写入任何内容', () async {
      final buffer = SseLogBuffer(store: store, maxCapacity: 10, batchSize: 5);

      // 空 buffer flush
      await buffer.flush();

      final file = File('${tempDir}${Platform.pathSeparator}network.log');
      // 文件可能不存在或为空
      if (await file.exists()) {
        final content = await file.readAsString();
        expect(content.trim().isEmpty, isTrue);
      }
    });
  });
}
