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
  var _needsRestore = false;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> enter() => _enqueue(() async {
    if (_entered) return;
    if (_needsRestore) await _restorePlatformState();
    _needsRestore = true;
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _entered = true;
    } catch (error, stackTrace) {
      // 任一步可能已产生平台副作用；立即补偿。补偿失败时保留
      // _needsRestore，页面退出仍会再次尝试完整恢复。
      try {
        await _restorePlatformState();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  @override
  Future<void> restore() => _enqueue(() async {
    if (!_needsRestore) return;
    await _restorePlatformState();
  });

  Future<void> _restorePlatformState() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _entered = false;
    _needsRestore = false;
  }

  /// 平台通道操作严格串行；失败只结束当前调用，后续恢复仍可重试。
  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
