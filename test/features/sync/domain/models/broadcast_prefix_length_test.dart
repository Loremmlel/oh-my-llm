import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/broadcast_prefix_length.dart';

void main() {
  group('BroadcastPrefixLength', () {
    test('默认值为 /24', () {
      expect(BroadcastPrefixLength.defaultValue, BroadcastPrefixLength.p24);
    });

    test('三个枚举值的 prefix / label 都正确', () {
      expect(BroadcastPrefixLength.p8.prefix, 8);
      expect(BroadcastPrefixLength.p8.label, '/8');
      expect(BroadcastPrefixLength.p16.prefix, 16);
      expect(BroadcastPrefixLength.p16.label, '/16');
      expect(BroadcastPrefixLength.p24.prefix, 24);
      expect(BroadcastPrefixLength.p24.label, '/24');
    });

    group('computeBroadcast', () {
      test('/24 模式下 10.214.98.86（手机热点）得到 10.214.98.255', () {
        // 回归原 Bug：旧启发式对 10.x 一律按 /8 算成 10.255.255.255
        final result = BroadcastPrefixLength.p24
            .computeBroadcast(InternetAddress('10.214.98.86'));
        expect(result.address, '10.214.98.255');
      });

      test('/24 模式下 192.168.1.100（家庭路由）得到 192.168.1.255', () {
        final result = BroadcastPrefixLength.p24
            .computeBroadcast(InternetAddress('192.168.1.100'));
        expect(result.address, '192.168.1.255');
      });

      test('/16 模式下 10.214.98.86 得到 10.214.255.255', () {
        final result = BroadcastPrefixLength.p16
            .computeBroadcast(InternetAddress('10.214.98.86'));
        expect(result.address, '10.214.255.255');
      });

      test('/8 模式下 10.214.98.86 得到 10.255.255.255（旧启发式结果）', () {
        // 用户主动选 /8 时会得到旧启发式的结果，行为可预期
        final result = BroadcastPrefixLength.p8
            .computeBroadcast(InternetAddress('10.214.98.86'));
        expect(result.address, '10.255.255.255');
      });

      test('非 IPv6 地址（raw.length != 4）回退到原地址对象', () {
        final v6 = InternetAddress('::1', type: InternetAddressType.IPv6);
        final result = BroadcastPrefixLength.p24.computeBroadcast(v6);
        expect(result.address, '::1');
      });
    });

    group('fromStorage', () {
      test('null 回退到默认值 /24', () {
        expect(BroadcastPrefixLength.fromStorage(null),
            BroadcastPrefixLength.p24);
      });

      test('8 还原为 /8', () {
        expect(BroadcastPrefixLength.fromStorage(8), BroadcastPrefixLength.p8);
      });

      test('16 还原为 /16', () {
        expect(
            BroadcastPrefixLength.fromStorage(16), BroadcastPrefixLength.p16);
      });

      test('24 还原为 /24', () {
        expect(
            BroadcastPrefixLength.fromStorage(24), BroadcastPrefixLength.p24);
      });

      test('非法值（如 20、999）回退到默认值 /24', () {
        expect(BroadcastPrefixLength.fromStorage(20),
            BroadcastPrefixLength.p24);
        expect(BroadcastPrefixLength.fromStorage(999),
            BroadcastPrefixLength.p24);
      });
    });

    test('toStorage 返回 prefix 数值', () {
      expect(BroadcastPrefixLength.p8.toStorage(), 8);
      expect(BroadcastPrefixLength.p16.toStorage(), 16);
      expect(BroadcastPrefixLength.p24.toStorage(), 24);
    });
  });
}
