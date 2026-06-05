import 'dart:io';

import 'network_interface_info.dart';

/// 网络接口工具函数。
///
/// 使用 [NetworkInterface.list] 枚举本机 IPv4 接口，并通过启发式算法
/// 推算子网广播地址（不依赖第三方网络信息库）。
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
          broadcast: _computeBroadcast(addr),
        ));
      }
    }
    return result;
  }

  /// 根据 IP 地址推算子网广播地址。
  ///
  /// 基于常见私有 IP 段的默认子网掩码进行启发式推算：
  /// - 10.x.x.x → /8  (掩码 255.0.0.0)
  /// - 172.16.x.x ~ 172.31.x.x → /16 (掩码 255.255.0.0)
  /// - 192.168.x.x → /24 (掩码 255.255.255.0)
  /// - 其他 → /24
  ///
  /// 在非常规子网配置下广播地址可能不准确，UI 会友善提示此局限。
  static String _computeBroadcast(InternetAddress addr) {
    final raw = addr.rawAddress;
    if (raw.length != 4) return addr.address;

    final ipInt =
        (raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3];
    int maskInt;

    if (raw[0] == 10) {
      // A 类私有：10.0.0.0/8 → 掩码 255.0.0.0
      maskInt = 0xFF000000;
    } else if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) {
      // B 类私有：172.16.0.0/12，但大多数家庭网络用 /16
      maskInt = 0xFFFF0000;
    } else if (raw[0] == 192 && raw[1] == 168) {
      // C 类私有：192.168.0.0/16，但大多数家庭网络用 /24
      maskInt = 0xFFFFFF00;
    } else {
      // 默认 /24
      maskInt = 0xFFFFFF00;
    }

    final broadcastInt = ipInt | (~maskInt & 0xFFFFFFFF);
    return '${(broadcastInt >> 24) & 0xFF}'
        '.${(broadcastInt >> 16) & 0xFF}'
        '.${(broadcastInt >> 8) & 0xFF}'
        '.${broadcastInt & 0xFF}';
  }
}
