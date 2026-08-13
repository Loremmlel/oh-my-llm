import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/data/udp/sync_udp_announcement_codec.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_version.dart';

/// UDP v3 公告信封纯编解码的契约测试。
void main() {
  group('SyncUdpAnnouncementCodec', () {
    const codec = SyncUdpAnnouncementCodec();

    /// 以 [overrides] 覆盖默认字段构造合法公告字节，用于逐字段破坏校验。
    Uint8List envelope([Map<String, Object?> overrides = const {}]) {
      final fields = <String, Object?>{
        'app': SyncUdpAnnouncementCodec.appId,
        'version': 3,
        'minProtocolVersion': 3,
        'maxProtocolVersion': 3,
        'deviceName': 'Test-PC',
        'serverId': 'server-1',
        'httpPort': 54321,
      }..addAll(overrides);
      return utf8.encode(jsonEncode(fields));
    }

    test('合法公告 round-trip 后可按来源地址解出服务端', () {
      const codec = SyncUdpAnnouncementCodec();
      final bytes = codec.encode(
        httpPort: 54321,
        deviceName: 'Test-PC',
        serverId: 'server-1',
      );
      final server = codec.decode(data: bytes, sourceAddress: '127.0.0.1');
      expect(server?.deviceName, 'Test-PC');
      expect(server?.httpPort, 54321);
      expect(server?.serverId, 'server-1');
      expect(server?.ip, '127.0.0.1');
      expect(server?.protocolRange, SyncProtocolRange.local);
    });

    group('decode 对非法公告一律返回 null', () {
      final rejects = <(String, Uint8List)>[
        ('顶层 JSON 是数组', utf8.encode('[1, 2, 3]')),
        ('顶层 JSON 是字符串', utf8.encode('"hello"')),
        ('app 不是 oh-my-llm', envelope({'app': 'other-app'})),
        ('version 不是 3', envelope({'version': 2})),
        ('version 是字符串', envelope({'version': '3'})),
        ('缺少 minProtocolVersion', envelope({'minProtocolVersion': null})),
        ('minProtocolVersion 非整数', envelope({'minProtocolVersion': '3'})),
        ('minProtocolVersion 为零', envelope({'minProtocolVersion': 0})),
        ('缺少 maxProtocolVersion', envelope({'maxProtocolVersion': null})),
        ('maxProtocolVersion 非整数', envelope({'maxProtocolVersion': '3'})),
        ('maxProtocolVersion 低于 minimum', envelope({'maxProtocolVersion': 2})),
        ('httpPort 为零', envelope({'httpPort': 0})),
        ('httpPort 超过 65535', envelope({'httpPort': 65536})),
        ('httpPort 非整数', envelope({'httpPort': '54321'})),
        ('serverId 为空字符串', envelope({'serverId': ''})),
        ('deviceName 全空白', envelope({'deviceName': '   '})),
        ('数据报不是合法 UTF-8', Uint8List.fromList([0xFF, 0xFE, 0x00])),
        ('数据报不是合法 JSON', utf8.encode('{not-json')),
      ];

      for (final (name, bytes) in rejects) {
        test(name, () {
          expect(codec.decode(data: bytes, sourceAddress: '127.0.0.1'), isNull);
        });
      }
    });
  });
}
