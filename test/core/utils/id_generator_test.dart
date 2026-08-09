import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/id_generator.dart';

void main() {
  group('generateEntityId', () {
    test('符合微秒时间戳与十六进制随机后缀格式', () {
      final id = generateEntityId();
      expect(id, matches(RegExp(r'^\d+-[0-9a-f]+$')));
      final parts = id.split('-');
      final timestamp = int.tryParse(parts.first);
      expect(timestamp, isNotNull);
      expect(timestamp, isPositive);
    });
  });
}
