import 'package:flutter/foundation.dart';

import 'package:oh_my_llm/app/attention/app_window.dart';
import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/app/platform/windows_app_window.dart';

/// AppWindow 工厂：由 [createAppWindow] 按宿主平台惰性选择。
typedef AppWindowFactory = AppWindow Function();

/// 按宿主平台选择应用窗口端口；生产调用不传 factory，使用文件内默认实现。
///
/// Windows 绑定 [WindowsAppWindow]（包装全局 windowManager 单例），其余平台
/// 绑定恒 focused 的 [NoopAppWindow]，绝不触碰 window_manager。测试选择
/// Windows 时必须注入返回 fake/no-op 的 [windowsFactory]，从构造源头阻止
/// 真实插件访问；与通知平台绑定工厂遵守同样的「只有被选中的 factory 可以
/// 执行」规则。
AppWindow createAppWindow({
  required TargetPlatform platform,
  AppWindowFactory? windowsFactory,
  AppWindowFactory? otherFactory,
}) {
  if (platform == TargetPlatform.windows) {
    return (windowsFactory ?? _defaultWindowsAppWindow)();
  }
  return (otherFactory ?? NoopAppWindow.new)();
}

AppWindow _defaultWindowsAppWindow() =>
    WindowsAppWindow(client: WindowManagerWindowsWindowClient());
