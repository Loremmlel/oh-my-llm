import 'dart:math';

/// 加密安全的随机数源，用于生成 ID 后缀，避免可预测碰撞。
final Random _random = Random.secure();

/// 生成一个业务实体 ID。
///
/// 格式为 `{微秒时间戳}-{随机十六进制后缀}`，例如：
/// `1714220012345678-a3f9c012`
///
/// 时间戳保证单机单线程的有序性，随机后缀降低同一微秒内并发碰撞的概率。
String generateEntityId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final suffix = _random.nextInt(1 << 32).toRadixString(16);
  return '$timestamp-$suffix';
}
