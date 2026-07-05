/// 媒体服务端连接信息。
///
/// 用于从 [DiscoveredServer] 转换到 media feature 内部类型，
/// 避免 media 层直接依赖 sync 层的 data 类型。
class MediaServerInfo {
  final String ip;
  final int httpPort;

  const MediaServerInfo({required this.ip, required this.httpPort});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaServerInfo && ip == other.ip && httpPort == other.httpPort;

  @override
  int get hashCode => Object.hash(ip, httpPort);
}
