import 'dart:io';

import 'network_interface_info.dart';

/// 网络接口工具函数。
///
/// 使用 [NetworkInterface.list] 枚举本机 IPv4 接口。
/// 广播地址不在此处计算，而由 [BroadcastPrefixLength] 配合用户选择实时推算。
class NetworkInterfaceUtils {
  NetworkInterfaceUtils._();

  /// 获取本机所有可用的 IPv4 网络接口（排除回环和链路本地）。
  static Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    final result = <NetworkInterfaceInfo>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.isLinkLocal) continue;
        result.add(NetworkInterfaceInfo(
          name: iface.name,
          ip: addr.address,
        ));
      }
    }
    return result;
  }
}
