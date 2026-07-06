/// 本机网络接口信息，用于局域网同步的网卡选择。
///
/// 广播地址不再在此处固化，而是由 [BroadcastPrefixLength] 配合本 IP 实时计算
/// （避免旧启发式对 10.x 段一律假设 /8 的 Bug）。
class NetworkInterfaceInfo {
  const NetworkInterfaceInfo({required this.name, required this.ip});

  /// 网卡名称（如 "Wi-Fi"、"以太网"、"wlan0"）。
  final String name;

  /// 本机在该接口上的 IPv4 地址。
  final String ip;

  /// 用于 UI 的展示标签。
  String get label => '$name — $ip';
}
