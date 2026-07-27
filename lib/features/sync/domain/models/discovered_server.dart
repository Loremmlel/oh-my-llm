import 'sync_protocol_version.dart';

/// 局域网内发现的远端 Sync 服务端信息。
final class DiscoveredServer {
  const DiscoveredServer({
    required this.deviceName,
    required this.ip,
    required this.httpPort,
    this.serverId = '',
    this.protocolRange = SyncProtocolRange.local,
  });

  final String deviceName;
  final String ip;
  final int httpPort;

  /// 稳定安装身份；仅用于匹配本地配对记录，UDP 本身不提供真实性。
  final String serverId;

  /// UDP 公告的兼容性元数据；不包含 token、授权或配对码。
  final SyncProtocolRange protocolRange;

  bool get isProtocolCompatible =>
      protocolRange.overlaps(SyncProtocolRange.local);
}
