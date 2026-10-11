import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 改名后仍沿用已发布的数据库和设置目录标识', () {
    final resource = File('windows/runner/Runner.rc').readAsStringSync();

    // path_provider 和 shared_preferences 共同用这两个资源字段定位已有数据。
    for (final entry in {
      'CompanyName': 'yuzu.shiki',
      'ProductName': 'oh_my_llm',
    }.entries) {
      final value = RegExp('VALUE\\s+"${entry.key}"\\s*,\\s*"([^"]*)"')
          .firstMatch(resource)
          ?.group(1);
      expect(value, entry.value, reason: '${entry.key} 改变会切换持久化目录');
    }
  });
}
