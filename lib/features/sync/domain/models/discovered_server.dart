/// 局域网内发现的远端 Sync 服务端信息。
final class DiscoveredServer {
  const DiscoveredServer({
    required this.deviceName,
    required this.ip,
    required this.httpPort,
  });

  final String deviceName;
  final String ip;
  final int httpPort;
}
