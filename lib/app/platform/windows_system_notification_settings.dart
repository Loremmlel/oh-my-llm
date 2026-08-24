import 'dart:io';

import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

import 'windows_notification_host_client.dart';

/// 进程启动 seam：把 [Process.start] 从设置 adapter 中隔离出来。
///
/// 只有生产实现真正拉起进程；测试注入受控 Fake 记录 executable/arguments/mode，
/// 不启动 explorer.exe。seam 刻意不暴露 runInShell，也不接受拼接后的命令
/// 字符串——打开系统设置的调用形态被固定为「可执行文件名 + 参数数组」。
abstract interface class WindowsProcessLauncher {
  /// 以指定模式启动外部进程；启动失败以异常表达，由调用方统一映射。
  Future<void> start({
    required String executable,
    required List<String> arguments,
    required ProcessStartMode mode,
  });
}

/// 生产进程启动器：直接转发 [Process.start]，由调用方决定进程模式。
final class SystemWindowsProcessLauncher implements WindowsProcessLauncher {
  const SystemWindowsProcessLauncher();

  @override
  Future<void> start({
    required String executable,
    required List<String> arguments,
    required ProcessStartMode mode,
  }) {
    return Process.start(executable, arguments, mode: mode);
  }
}

/// Windows 系统通知设置窄 adapter。
///
/// 状态只反映共享 [WindowsNotificationHostClient] 的可用性：runner 宿主可用
/// 即 available，不承诺系统开关开启或未来每次展示成功；未打包 API 无法可靠
/// 查询最终开关，因此绝不伪造系统级精确开关读取。打开设置页固定以分离模式
/// 调用 `explorer.exe` 与参数数组 `ms-settings:notifications`，失败 fail-open
/// 为 false，不向调用方抛出。
final class WindowsSystemNotificationSettings
    implements SystemNotificationSettings {
  WindowsSystemNotificationSettings({
    required WindowsNotificationHostClient client,
    WindowsProcessLauncher launcher = const SystemWindowsProcessLauncher(),
  }) : _client = client,
       _launcher = launcher;

  final WindowsNotificationHostClient _client;
  final WindowsProcessLauncher _launcher;

  @override
  Future<SystemNotificationStatus> getStatus() async {
    try {
      return await _client.getAvailable()
          ? SystemNotificationStatus.available
          : SystemNotificationStatus.unavailable;
    } catch (_) {
      return SystemNotificationStatus.unavailable;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      await _launcher.start(
        executable: 'explorer.exe',
        arguments: const ['ms-settings:notifications'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
