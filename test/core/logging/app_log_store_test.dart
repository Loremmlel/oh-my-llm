import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
