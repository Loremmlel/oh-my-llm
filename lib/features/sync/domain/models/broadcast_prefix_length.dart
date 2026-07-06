import 'dart:io';

/// 同步广播使用的子网掩码长度选项。
///
/// 用户在 UI 显式选择，服务端启动时据此推算子网广播地址。
/// 默认 /24 是绝大多数家庭路由器和手机热点的常见子网大小。
enum BroadcastPrefixLength {
  p8(8, 0xFF000000, '/8'),
  p16(16, 0xFFFF0000, '/16'),
  p24(24, 0xFFFFFF00, '/24');

  const BroadcastPrefixLength(this.prefix, this.maskInt, this.label);

  /// CIDR 前缀长度（如 8、16、24）。
  final int prefix;

  /// 对应的 32 位子网掩码（如 0xFF000000 = 255.0.0.0）。
  final int maskInt;

  /// UI 展示文本（如 '/24'）。
  final String label;

  /// 默认子网掩码，对应大多数家用网络与手机热点的子网大小。
  static const BroadcastPrefixLength defaultValue = BroadcastPrefixLength.p24;

  /// 把 IPv4 地址按当前 prefix 推算子网广播地址。
  /// 非 IPv4（raw.length != 4）回退到原地址对象。
  InternetAddress computeBroadcast(InternetAddress addr) {
    final raw = addr.rawAddress;
    if (raw.length != 4) return addr;
    final ipInt =
        (raw[0] << 24) | (raw[1] << 16) | (raw[2] << 8) | raw[3];
    final broadcastInt = ipInt | (~maskInt & 0xFFFFFFFF);
    return InternetAddress(
      '${(broadcastInt >> 24) & 0xFF}'
      '.${(broadcastInt >> 16) & 0xFF}'
      '.${(broadcastInt >> 8) & 0xFF}'
      '.${broadcastInt & 0xFF}',
    );
  }

  /// 从持久化值还原枚举（容忍 null 与非法值，回退到默认 /24）。
  static BroadcastPrefixLength fromStorage(int? value) {
    for (final v in values) {
      if (v.prefix == value) return v;
    }
    return defaultValue;
  }

  /// 持久化到 SharedPreferences 时使用的整数值（与 prefix 相同）。
  int toStorage() => prefix;
}
