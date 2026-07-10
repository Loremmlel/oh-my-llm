import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/broadcast_prefix_length.dart';

void main() {
  group('BroadcastPrefixLength', () {
    group('computeBroadcast', () {
      const cases = <(BroadcastPrefixLength, String, String)>[
        (BroadcastPrefixLength.p24, '10.214.98.86', '10.214.98.255'),
        (BroadcastPrefixLength.p24, '192.168.1.100', '192.168.1.255'),
        (BroadcastPrefixLength.p16, '10.214.98.86', '10.214.255.255'),
        (BroadcastPrefixLength.p8, '10.214.98.86', '10.255.255.255'),
      ];
      for (final (prefix, ip, expected) in cases) {
        test('/${prefix.prefix} 模式下 $ip 得到 $expected', () {
          final result = prefix.computeBroadcast(InternetAddress(ip));
          expect(result.address, expected);
        });
      }

      test('非 IPv4 地址（raw.length != 4）回退到原地址对象', () {
        final v6 = InternetAddress('::1', type: InternetAddressType.IPv6);
        final result = BroadcastPrefixLength.p24.computeBroadcast(v6);
        expect(result.address, '::1');
      });
    });

    group('fromStorage', () {
      const cases = <(String, int?, BroadcastPrefixLength)>[
        ('null', null, BroadcastPrefixLength.p24),
        ('8', 8, BroadcastPrefixLength.p8),
        ('16', 16, BroadcastPrefixLength.p16),
        ('24', 24, BroadcastPrefixLength.p24),
        ('非法值 20', 20, BroadcastPrefixLength.p24),
        ('非法值 999', 999, BroadcastPrefixLength.p24),
      ];
      for (final (name, input, expected) in cases) {
        test('fromStorage($name) → $expected', () {
          expect(BroadcastPrefixLength.fromStorage(input), expected);
        });
      }
    });
  });
}
