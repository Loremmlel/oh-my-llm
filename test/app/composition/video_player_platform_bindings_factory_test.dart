import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/composition/video_player_platform_bindings_factory.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/media/helpers/fake_video_player_platform_bindings.dart';

void main() {
  test('Windows 每次创建独立 Desktop bindings', () {
    final factory = createVideoPlayerPlatformBindingsFactory(
      platform: TargetPlatform.windows,
      windowsFullscreenFactory: () => FakeVideoFullscreenController(),
      mobileSystemUiFactory: () => FakeMobileVideoSystemUiController(),
    );
    final first = factory();
    final second = factory();
    expect(first, isA<DesktopVideoPlayerBindings>());
    expect(second, isA<DesktopVideoPlayerBindings>());
    expect(identical(first, second), isFalse);
  });

  test('Android 创建 Mobile bindings 且不调用 Windows factory', () {
    var windowsCalls = 0;
    final factory = createVideoPlayerPlatformBindingsFactory(
      platform: TargetPlatform.android,
      windowsFullscreenFactory: () {
        windowsCalls++;
        return FakeVideoFullscreenController();
      },
      mobileSystemUiFactory: () => FakeMobileVideoSystemUiController(),
    );
    expect(factory(), isA<MobileVideoPlayerBindings>());
    expect(windowsCalls, 0);
  });

  test('非 Windows/Android 平台抛出固定安全消息，不默认回退 Mobile', () {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        () => createVideoPlayerPlatformBindingsFactory(
          platform: platform,
          windowsFullscreenFactory: () => FakeVideoFullscreenController(),
          mobileSystemUiFactory: () => FakeMobileVideoSystemUiController(),
        )(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            '视频播放器仅支持 Windows 与 Android 平台',
          ),
        ),
      );
    }
  });
}
