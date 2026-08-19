import 'dart:convert';

import '../../domain/models/discovery/discovered_server.dart';
import '../../domain/models/protocol/sync_protocol_version.dart';

/// UDP v4 公告信封的纯编解码边界。
///
/// 只负责公告数据报的编码与校验，不接触 socket、定时器或平台通道；
/// [decode] 对任何非法输入返回 null 而不抛异常，discovery 可直接短路。
final class SyncUdpAnnouncementCodec {
  const SyncUdpAnnouncementCodec();

  /// 公告声明的应用标识；与局域网 HTTP 握手保持一致。
  static const String appId = 'oh-my-llm';

  /// 公告固定声明的协议版本（Sync v4）。
  static const int version = SyncProtocolVersionPolicy.current;

  /// 编码公告数据报，字段名与取值保持 v4 线上字节格式不变。
  List<int> encode({
    required int httpPort,
    required String deviceName,
    required String serverId,
  }) {
    return utf8.encode(
      jsonEncode({
        'app': appId,
        'version': version,
        'minProtocolVersion': SyncProtocolRange.local.minimum,
        'maxProtocolVersion': SyncProtocolRange.local.maximum,
        'deviceName': deviceName,
        'serverId': serverId,
        'httpPort': httpPort,
      }),
    );
  }

  /// 解码并校验公告数据报；任一字段不合法即返回 null。
  DiscoveredServer? decode({
    required List<int> data,
    required String sourceAddress,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['app'] != appId) return null;
    if (decoded['version'] != version) return null;

    final minimum = decoded['minProtocolVersion'];
    final maximum = decoded['maxProtocolVersion'];
    final port = decoded['httpPort'];
    final serverId = decoded['serverId'];
    final deviceName = decoded['deviceName'];
    if (minimum is! int ||
        minimum < 1 ||
        maximum is! int ||
        maximum < minimum ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        serverId is! String ||
        serverId.isEmpty ||
        deviceName is! String ||
        deviceName.trim().isEmpty) {
      return null;
    }
    return DiscoveredServer(
      deviceName: deviceName,
      ip: sourceAddress,
      httpPort: port,
      serverId: serverId,
      protocolRange: SyncProtocolRange(minimum: minimum, maximum: maximum),
    );
  }
}
