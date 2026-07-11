import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/app_network_logger.dart';
import 'package:oh_my_llm/core/logging/app_log_store.dart';

void main() {
  late Directory _directory;
  late File _logFile;

  setUp(() async {
    _directory = await Directory.systemTemp.createTemp('log-store-test-');
    addTearDown(() async {
      if (await _directory.exists()) {
        await _directory.delete(recursive: true);
      }
    });
    _logFile = File(
      '${_directory.path}${Platform.pathSeparator}network.log',
    );
  });

  test('AppLogStore rotates file when size exceeds max bytes', () async {
    final store = await AppLogStore.open(
      directoryPath: _directory.path,
      fileName: 'network.log',
      maxBytes: 40,
    );

    await store.appendLine('0123456789');
    await store.appendLine('abcdefghij');
    await store.appendLine('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');

    final content = await _logFile.readAsString();
    expect(content, contains('[log-rotated]'));
  });

  test(
    'AppNetworkLogger keeps request logs across relaunches and detach',
    () async {
      final logger = AppNetworkLogger(
        store: await AppLogStore.open(directoryPath: _directory.path),
      );

      await logger.onAppLaunch();
      await logger.logRequest(
        uri: Uri.parse('https://api.example.com/v1/chat/completions'),
        method: 'POST',
        headers: const {
          'Authorization': 'Bearer sk-test-12345678',
          'Content-Type': 'application/json',
        },
        payload: const {
          'model': 'demo-model',
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
        },
      );
      await logger.onAppDetached();

      final relaunchedLogger = AppNetworkLogger(
        store: await AppLogStore.open(directoryPath: _directory.path),
      );
      await relaunchedLogger.onAppLaunch();

      final content = await _logFile.readAsString();
      expect(
        content,
        contains('[request] POST https://api.example.com/v1/chat/completions'),
      );
      expect(content, contains('"messages"'));
      expect(content, isNot(contains('[log-cleared]')));
    },
  );

  test('AppNetworkLogger writes non-stream response bodies', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: _directory.path),
    );

    await logger.logResponseBody(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      body: const {
        'choices': [
          {
            'message': {'content': '完整回复', 'reasoning_content': '完整思考'},
          },
        ],
      },
    );

    final content = await _logFile.readAsString();
    expect(content, contains('[response-body]'));
    expect(content, contains('完整回复'));
    expect(content, contains('完整思考'));
  });

  test('AppLogStore.clear writes log-cleared marker with reason', () async {
    final store = await AppLogStore.open(directoryPath: _directory.path);

    await store.appendLine('first line');
    await store.clear(reason: 'test rotation');

    final content = await _logFile.readAsString();
    expect(content, contains('[log-cleared] test rotation'));
    expect(content, isNot(contains('first line')));
  });

  test('AppNetworkLogger.logResponse writes status and elapsed', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: _directory.path),
    );

    await logger.logResponse(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      statusCode: 200,
      headers: const {'Content-Type': 'application/json'},
      elapsed: const Duration(milliseconds: 42),
    );

    final content = await _logFile.readAsString();
    expect(content, contains('[response]'));
    expect(content, contains('status=200'));
    expect(content, contains('elapsedMs=42'));
  });

  test('AppNetworkLogger.logSseLine parses JSON line', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: _directory.path),
    );

    await logger.logSseLine(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      line: '{"content":"hello"}',
    );

    final content = await _logFile.readAsString();
    expect(content, contains('[sse]'));
    expect(content, contains('hello'));
  });

  test('AppNetworkLogger.logSseLine falls back to text for invalid JSON', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: _directory.path),
    );

    await logger.logSseLine(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      line: 'not-json-at-all',
    );

    final content = await _logFile.readAsString();
    expect(content, contains('[sse]'));
    expect(content, contains('not-json-at-all'));
  });

  test('AppNetworkLogger.logError truncates stack trace to 12 lines', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: _directory.path),
    );

    // 构造一个 20 行的 StackTrace
    final stackLines = List.generate(20, (i) => '#$i some-frame ($i)');
    final stackTrace = StackTrace.fromString(stackLines.join('\n'));

    await logger.logError(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      error: 'test error',
      stackTrace: stackTrace,
    );

    final content = await _logFile.readAsString();
    expect(content, contains('[error]'));
    expect(content, contains('test error'));
    // 前 12 行被写入，第 13 行（#12）不应出现
    expect(content, contains('#11 some-frame'));
    expect(content, isNot(contains('#12 some-frame')));
  });
}
