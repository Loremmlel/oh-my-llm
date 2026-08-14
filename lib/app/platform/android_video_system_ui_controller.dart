import 'package:flutter/services.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

/// Android 沉浸式系统 UI 会话：实现 presentation 的
/// [MobileVideoSystemUiController] 窄端口。
///
/// 进入时请求允许方向并切换 immersiveSticky；恢复时回到 manual 全 overlay
/// 并放开全部方向。restore 幂等：只在已进入时执行一次，重复到达不重复调用
/// SystemChrome。页面经 bindings 持有本会话，不再直接调用 SystemChrome。
final class AndroidVideoSystemUiController
    implements MobileVideoSystemUiController {
  var _entered = false;

  @override
  Future<void> enter() async {
    if (_entered) return;
    _entered = true;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Future<void> restore() async {
    if (!_entered) return;
    _entered = false;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
