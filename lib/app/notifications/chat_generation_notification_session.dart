import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 生成进程级通知 session ID：128-bit 安全随机，编码为 32 位小写十六进制。
///
/// 不持久化、不复用、不来自会话或用户数据，也不进入通知文案或日志；
/// 用于 event key 命名（`v1:<session>:<generationId>:<kind>`），保证进程
/// 重启后即使 generationId 从 1 重新计数也不会复用旧通知 ID/Tag/PendingIntent。
String createChatGenerationNotificationSessionId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i += 1) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// 进程级通知 session ID provider。
///
/// 一个 root ProviderScope 内只创建一次；coordinator（ongoing payload）与
/// 默认终态通知深模块（收据）必须读取同一个值，不得各生成一份。测试必须
/// override 固定 session，不读取时间或全局随机状态。
final chatGenerationNotificationSessionIdProvider = Provider<String>((ref) {
  return createChatGenerationNotificationSessionId();
});
