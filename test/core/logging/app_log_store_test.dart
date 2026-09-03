import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/app_network_logger.dart';
import 'package:oh_my_llm/core/logging/app_log_store.dart';

void main() {
  late Directory directory;
  late File logFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('log-store-test-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    logFile = File('${directory.path}${Platform.pathSeparator}network.log');
  });

  test('日志文件超过容量时轮转', () async {
    final store = await AppLogStore.open(
      directoryPath: directory.path,
      fileName: 'network.log',
      maxBytes: 40,
    );

    await store.appendLine('0123456789');
    await store.appendLine('abcdefghij');
    await store.appendLine('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');

    final content = await logFile.readAsString();
    expect(content, contains('[log-rotated]'));
  });

  test('请求日志跨应用重启保留且不会被 detach 清空', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
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
      logBody: true,
    );
    await logger.onAppDetached();

    final relaunchedLogger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );
    await relaunchedLogger.onAppLaunch();

    final content = await logFile.readAsString();
    expect(
      content,
      contains('[request] POST https://api.example.com/v1/chat/completions'),
    );
    expect(content, contains('"messages"'));
    expect(content, isNot(contains('[log-cleared]')));
  });

  test('批量写入后清空文件并记录原因', () async {
    final store = await AppLogStore.open(directoryPath: directory.path);

    await store.appendLines(['line-A', 'line-B']);
    expect(await logFile.readAsString(), contains('line-B'));
    await store.clear(reason: 'test rotation');

    final content = await logFile.readAsString();
    expect(content, contains('[log-cleared] test rotation'));
    expect(content, isNot(contains('line-A')));
  });

  test('响应日志写入状态、耗时和启用的正文', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );

    await logger.logResponse(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      statusCode: 200,
      headers: const {'Content-Type': 'application/json'},
      elapsed: const Duration(milliseconds: 42),
    );
    await logger.logResponseBody(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      body: const {'content': '完整回复', 'reasoning_content': '完整思考'},
      logBody: true,
    );

    final content = await logFile.readAsString();
    expect(content, contains('[response]'));
    expect(content, contains('status=200'));
    expect(content, contains('elapsedMs=42'));
    expect(content, contains('[response-body]'));
    expect(content, contains('完整回复'));
    expect(content, contains('完整思考'));
  });

  test('SSE 日志同时接受 JSON 和普通文本', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );

    await logger.logSseLine(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      line: '{"content":"hello"}',
    );
    await logger.logSseLine(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      line: 'not-json-at-all',
    );
    await logger.drain();

    final content = await logFile.readAsString();
    expect(content, contains('[sse]'));
    expect(content, contains('hello'));
    expect(content, contains('not-json-at-all'));
  });

  test('错误日志把堆栈截断为十二行', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );

    // 构造一个 20 行的 StackTrace
    final stackLines = List.generate(20, (i) => '#$i some-frame ($i)');
    final stackTrace = StackTrace.fromString(stackLines.join('\n'));

    await logger.logError(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      error: 'test error',
      stackTrace: stackTrace,
    );

    final content = await logFile.readAsString();
    expect(content, contains('[error]'));
    expect(content, contains('test error'));
    // 前 12 行被写入，第 13 行（#12）不应出现
    expect(content, contains('#11 some-frame'));
    expect(content, isNot(contains('#12 some-frame')));
  });

  test('正文日志关闭时请求与响应都不写入正文', () async {
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );

    await logger.logResponseBody(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      body: const {'secret': 'should-not-appear'},
      logBody: false,
    );
    await logger.logRequest(
      uri: Uri.parse('https://api.example.com/v1/chat/completions'),
      method: 'POST',
      headers: const {'Content-Type': 'application/json'},
      payload: const {'model': 'gpt-4'},
      logBody: false,
    );

    final content = await logFile.readAsString();
    expect(content, contains('[request]'));
    expect(content, isNot(contains('[response-body]')));
    expect(content, isNot(contains('should-not-appear')));
    expect(content, isNot(contains('payload=')));
  });
}
