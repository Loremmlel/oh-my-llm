import 'package:flutter/foundation.dart';

import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 按宿主平台选择生成前台服务端口的纯工厂。
///
/// Android 绑定 [AndroidChatGenerationForegroundService]，其余平台（Windows /
/// Linux / macOS / iOS / Fuchsia）统一绑定 [NoopChatGenerationForegroundService]，
/// 绝不创建 Android adapter、不发起任何 MethodChannel 调用。
///
/// [androidFactory] 供测试注入受控 adapter；生产默认构造真实 adapter。
ChatGenerationForegroundServicePort createChatGenerationForegroundService({
  required TargetPlatform platform,
  AndroidChatGenerationForegroundService Function()? androidFactory,
}) {
  if (platform == TargetPlatform.android) {
    return (androidFactory ?? AndroidChatGenerationForegroundService.new)();
  }
  return NoopChatGenerationForegroundService();
}
