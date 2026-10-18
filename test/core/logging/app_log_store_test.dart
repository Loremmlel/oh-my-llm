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
