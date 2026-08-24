import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_system_notification_settings.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/noop_system_notification_settings.dart';
import 'package:oh_my_llm/app/platform/windows_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';
import 'package:oh_my_llm/app/platform/windows_system_notification_settings.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// 单个平台的一整套生成通知绑定。
///
/// [foregroundService] / [terminalAdapter] / [systemNotificationSettings]
/// 是三个窄角色端口；[disposeShared] 是共享 owner（Android bridge 或
/// Windows host client）的唯一释放入口。端口各自的 dispose 绝不触碰共享
/// owner，避免重复释放；Dart 侧 dispose 也不关闭 runner 的原生资源——
/// runner-owned WindowsNotificationHost 的生命周期归 `main.cpp` 所有，
/// 在 Dart composition 之前启动，不归 Provider 生命周期所有。
typedef ChatGenerationNotificationPlatformBindings = ({
  ChatGenerationForegroundServicePort foregroundService,
  ChatGenerationTerminalNotificationAdapter terminalAdapter,
  SystemNotificationSettings systemNotificationSettings,
  Future<void> Function() disposeShared,
});

/// 平台绑定工厂：由 [createChatGenerationNotificationPlatformBindings] 按
/// 宿主平台惰性选择，只有被选中的 factory 可以执行。
typedef ChatGenerationNotificationPlatformBindingsFactory =
    ChatGenerationNotificationPlatformBindings Function();

/// 平台绑定记录的单例挂载点。
///
/// appCompositionOverrides 用工厂覆盖本 provider 并注册唯一 shared
/// disposer；三个角色 provider 分别投影记录字段，保证一次创建、一处释放。
final chatGenerationNotificationPlatformBindingsProvider =
    Provider<ChatGenerationNotificationPlatformBindings>(
      (ref) => throw UnsupportedError('生成通知平台绑定必须由 app composition 装配'),
    );

/// 按宿主平台选择一整套生成通知绑定；生产调用不传 factory，使用文件内
/// 默认实现。测试选择 Android/Windows 时必须注入返回 fake/no-op 记录的
/// 对应 factory，从构造源头阻止真实 MethodChannel client。
ChatGenerationNotificationPlatformBindings
createChatGenerationNotificationPlatformBindings({
  required TargetPlatform platform,
  ChatGenerationNotificationPlatformBindingsFactory? androidFactory,
  ChatGenerationNotificationPlatformBindingsFactory? windowsFactory,
  ChatGenerationNotificationPlatformBindingsFactory? otherFactory,
}) {
  return switch (platform) {
    // 只有被选中的分支会执行构造；绝不先构造所有平台 adapter 再选记录。
    TargetPlatform.android =>
      androidFactory ?? createAndroidChatGenerationNotificationPlatformBindings,
    TargetPlatform.windows =>
      windowsFactory ?? createWindowsChatGenerationNotificationPlatformBindings,
    _ => otherFactory ?? createOtherPlatformChatGenerationNotificationBindings,
  }();
}

/// Android 装配：一个共享 bridge 由三个窄 adapter 共享，[disposeShared] 只
/// dispose bridge 一次。测试可注入受控 [bridge] 验证共享与释放语义。
ChatGenerationNotificationPlatformBindings
createAndroidChatGenerationNotificationPlatformBindings({
  AndroidChatGenerationPlatformBridge? bridge,
}) {
  final sharedBridge = bridge ?? AndroidChatGenerationPlatformBridge();
  // once 守卫：disposeShared 是共享 owner 的唯一释放入口，重复调用不得
  // 二次触达 bridge。
  var sharedDisposed = false;
  return (
    foregroundService: AndroidChatGenerationForegroundService(
      bridge: sharedBridge,
    ),
    terminalAdapter: AndroidChatGenerationTerminalNotificationAdapter(
      bridge: sharedBridge,
    ),
    systemNotificationSettings: AndroidSystemNotificationSettings(
      bridge: sharedBridge,
    ),
    disposeShared: () async {
      if (sharedDisposed) return;
      sharedDisposed = true;
      sharedBridge.dispose();
    },
  );
}

/// Windows 装配：一个共享 host client 由 terminal adapter 与 settings 共享，
/// 前台使用 no-op，[disposeShared] 只 dispose client 一次。测试可通过
/// [hostClientFactory] 注入受控 client，从构造源头阻止真实 MethodChannel。
ChatGenerationNotificationPlatformBindings
createWindowsChatGenerationNotificationPlatformBindings({
  WindowsNotificationHostClient Function()? hostClientFactory,
}) {
  final sharedClient =
      hostClientFactory?.call() ?? MethodChannelWindowsNotificationHostClient();
  // once 守卫：disposeShared 是共享 owner 的唯一释放入口，重复调用不得
  // 二次触达 client；client.dispose 本身只撤销 Dart handler/关闭流，绝不
  // 关闭 runner 的 COM class object、mutex、pipe 或原生队列。
  var sharedDisposed = false;
  return (
    foregroundService: NoopChatGenerationForegroundService(),
    terminalAdapter: WindowsChatGenerationTerminalNotificationAdapter(
      client: sharedClient,
    ),
    systemNotificationSettings: WindowsSystemNotificationSettings(
      client: sharedClient,
    ),
    disposeShared: () async {
      if (sharedDisposed) return;
      sharedDisposed = true;
      await sharedClient.dispose();
    },
  );
}

/// 其余平台（Linux / macOS / iOS / Fuchsia）装配：三个 no-op，不发起任何
/// 平台调用。
ChatGenerationNotificationPlatformBindings
createOtherPlatformChatGenerationNotificationBindings() {
  return (
    foregroundService: NoopChatGenerationForegroundService(),
    terminalAdapter: NoopChatGenerationTerminalNotificationAdapter(),
    systemNotificationSettings: NoopSystemNotificationSettings(),
    disposeShared: () async {},
  );
}
