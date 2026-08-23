### Task 4：Android 共享 bridge

**文件**

- 新增 `lib/app/platform/android_chat_generation_platform_bridge.dart`
- 新增 `lib/app/platform/android_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/android_system_notification_settings.dart`
- 修改 `lib/app/platform/android_chat_generation_foreground_service.dart`
- 新增 `test/app/platform/android_chat_generation_platform_bridge_test.dart`
- 新增 `test/app/platform/android_chat_generation_terminal_notification_adapter_test.dart`
- 新增 `test/app/platform/android_system_notification_settings_test.dart`
- 修改 `test/app/platform/android_chat_generation_foreground_service_test.dart`

**RED 测试**

- `三个 Android 窄适配器共享一个 channel handler`
- `前台适配器只编码 ongoing 方法`
- `终态适配器只发送安全通知字段`
- `foreground start update 原样传输 Dart 预编码 timeout activation payload`
- `stop open timeout terminal activation 回调分发到对应窄流`
- `pending activation 只取一次`
- `timeout action stream 无 listener 时 ACK 为 false`
- `channel timeout 和 PlatformException 均映射为 fail-open 结果`
- `Android 设置状态和打开动作只委托共享 bridge`
- `dispose 后 callback 不再分发且可重复 dispose`

**GREEN**

- channel owner 只存在于 bridge。
- 本 Task 暂时使用现有 `yuzu.shiki.oh_my_llm/chat_generation_foreground` channel 名，保证此提交与尚未修改的 Kotlin runtime 可协作；Task 5 在同一个原子改动中同时切换 Dart/Kotlin 到最终 `.../chat_generation_notifications`。不得双写或安装双 handler。
- command timeout 沿用现有 2 秒。
- 所有原生错误只映射为固定分类。
- 三个新增测试分别写 `logs/android-bridge-green.log`、`logs/android-terminal-adapter-green.log`、`logs/android-system-notification-settings-green.log`；修改后的 foreground adapter 测试写 `logs/android-foreground-adapter-green.log`。每个单文件工具超时 60000ms。

**停止条件**

- 同一 MethodChannel 被两个 Dart 对象安装 handler。
- 为兼容旧 runtime channel 新增双写/双 handler。

