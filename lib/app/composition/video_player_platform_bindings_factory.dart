import 'package:flutter/foundation.dart';

import 'package:oh_my_llm/app/platform/android_video_system_ui_controller.dart';
import 'package:oh_my_llm/app/platform/windows_video_fullscreen_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

/// 唯一 TargetPlatform → bindings 选择点：每次调用返回一个可再次调用的工厂，
/// 页面每次打开视频时调用一次，生成互不共享瞬态的 bindings。
///
/// 平台与两端工厂都显式注入，便于测试传 Fake 端口；不支持的非 Windows/Android
/// 平台必须抛出固定安全消息，绝不默认回退 Mobile。
VideoPlayerPlatformBindingsFactory createVideoPlayerPlatformBindingsFactory({
  required TargetPlatform platform,
  required VideoFullscreenController Function() windowsFullscreenFactory,
  required MobileVideoSystemUiController Function() mobileSystemUiFactory,
}) {
  return switch (platform) {
    TargetPlatform.windows => () => DesktopVideoPlayerBindings(
      fullscreen: windowsFullscreenFactory(),
    ),
    TargetPlatform.android => () => MobileVideoPlayerBindings(
      systemUi: mobileSystemUiFactory(),
    ),
    _ => () => throw UnsupportedError('视频播放器仅支持 Windows 与 Android 平台'),
  };
}

/// 生产 bindings factory wrapper：读取 [defaultTargetPlatform]，绑定真实
/// Windows 全屏 adapter 与 Android SystemChrome adapter。
///
/// media presentation 不 import 平台 globals；平台选择只发生在 app composition。
VideoPlayerPlatformBindingsFactory createAppVideoPlayerBindingsFactory() =>
    createVideoPlayerPlatformBindingsFactory(
      platform: defaultTargetPlatform,
      windowsFullscreenFactory: () => WindowsVideoFullscreenController(
        gateway: WindowManagerVideoWindowGateway(),
      ),
      mobileSystemUiFactory: AndroidVideoSystemUiController.new,
    );
