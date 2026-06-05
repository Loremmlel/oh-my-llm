/// 本机网络接口信息，用于局域网同步的网段选择。
class NetworkInterfaceInfo {
  const NetworkInterfaceInfo({
    required this.name,
    required this.ip,
    required this.broadcast,
  });

  /// 网卡名称（如 "Wi-Fi"、"以太网"、"wlan0"）。
  final String name;

  /// 本机在该接口上的 IPv4 地址。
  final String ip;

  /// 子网广播地址（启发式推算，非常规子网可能不准确）。
  final String broadcast;

  /// 用于 UI 的展示标签。
  String get label => '$name — $ip';
}
