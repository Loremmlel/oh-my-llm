import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android MulticastLock 的边界：允许接收 UDP 广播包。
abstract interface class SyncMulticastLock {
  Future<void> acquire();
  Future<void> release();
}

const MethodChannel _multicastChannel = MethodChannel(
  'yuzu.shiki.oh_my_llm/multicast_lock',
);

/// 生产实现：非 Android 平台空操作；Android 上调用原 MethodChannel，
/// 通道失败只记录日志、不阻断发现流程（与旧行为一致）。
final class PlatformSyncMulticastLock implements SyncMulticastLock {
  const PlatformSyncMulticastLock();

  @override
  Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _multicastChannel.invokeMethod('acquire');
    } catch (e) {
      debugPrint('获取 MulticastLock 失败: $e');
    }
  }

  @override
  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _multicastChannel.invokeMethod('release');
    } catch (e) {
      debugPrint('释放 MulticastLock 失败: $e');
    }
  }
}
