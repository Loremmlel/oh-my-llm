import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/app_network_logger.dart';
import 'package:oh_my_llm/core/logging/app_log_store.dart';

void main() {
  test('AppLogStore rotates file when size exceeds max bytes', () async {
    final directory = await Directory.systemTemp.createTemp('log-store-test-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = await AppLogStore.open(
      directoryPath: directory.path,
      fileName: 'network.log',
      maxBytes: 40,
    );

    await store.appendLine('0123456789');
    await store.appendLine('abcdefghij');
    await store.appendLine('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');

    final file = File('${directory.path}${Platform.pathSeparator}network.log');
    final content = await file.readAsString();
    expect(content, contains('[log-rotated]'));
  });

  test(
    'AppNetworkLogger keeps request logs across relaunches and detach',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'network-log-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final file = File(
        '${directory.path}${Platform.pathSeparator}network.log',
      );
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
      );
      await logger.onAppDetached();

      final relaunchedLogger = AppNetworkLogger(
        store: await AppLogStore.open(directoryPath: directory.path),
      );
      await relaunchedLogger.onAppLaunch();

      final content = await file.readAsString();
      expect(
        content,
        contains('[request] POST https://api.example.com/v1/chat/completions'),
      );
      expect(content, contains('"messages"'));
      expect(content, isNot(contains('[log-cleared]')));
    },
  );
}
