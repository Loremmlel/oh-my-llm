import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/id_generator.dart';

void main() {
  group('generateEntityId', () {
    test('返回非空字符串', () {
      final id = generateEntityId();
      expect(id, isNotEmpty);
    });

    test('包含时间戳-随机后缀的分隔符', () {
      final id = generateEntityId();
      expect(id.contains('-'), isTrue);
    });

    test('时间戳前缀为正整数', () {
      final id = generateEntityId();
      final parts = id.split('-');
      expect(parts.length, greaterThanOrEqualTo(2));
      final timestamp = int.tryParse(parts.first);
      expect(timestamp, isNotNull);
      expect(timestamp! > 0, isTrue);
    });

    test('连续生成 100 次无碰撞', () {
      final ids = <String>{};
      for (var i = 0; i < 100; i += 1) {
        ids.add(generateEntityId());
      }
      expect(ids.length, equals(100));
    });

    test('后缀为合法十六进制', () {
      final id = generateEntityId();
      final suffix = id.split('-').sublist(1).join('-');
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(suffix), isTrue);
    });
  });
}
