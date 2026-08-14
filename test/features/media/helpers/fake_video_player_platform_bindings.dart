import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

/// 用于测试的 Fake 全屏控制器：记录精确调用顺序，支持确定性失败。
///
/// `calls` 按调用顺序追加方法名；`failNext` 让下一次 [toggle] 返回
/// consumed=true / succeeded=false 的失败结果。
final class FakeVideoFullscreenController implements VideoFullscreenController {
  bool actual = false;
  bool desired = false;
  bool failNext = false;
  final calls = <String>[];

  @override
  bool get actualFullscreen => actual;
  @override
  bool get desiredFullscreen => desired;

  @override
  Future<void> initializeSession() async => calls.add('initialize');

  @override
  Future<VideoFullscreenCommandResult> toggle() async {
    calls.add('toggle');
    if (failNext) {
      failNext = false;
      return const VideoFullscreenCommandResult(
        consumed: true,
        succeeded: false,
      );
    }
    desired = !desired;
    actual = desired;
    return const VideoFullscreenCommandResult(consumed: true, succeeded: true);
  }

  @override
  Future<VideoFullscreenCommandResult> exitIfFullscreen() async {
    calls.add('exitIfFullscreen');
    if (!desired && !actual) {
      return const VideoFullscreenCommandResult(
        consumed: false,
        succeeded: true,
      );
    }
    desired = false;
    actual = false;
    return const VideoFullscreenCommandResult(consumed: true, succeeded: true);
  }

  @override
  Future<bool> restoreAndDispose() async {
    calls.add('restoreAndDispose');
    return true;
  }
}

/// 用于测试的 Fake 移动系统 UI 控制器：记录进入/恢复调用顺序。
final class FakeMobileVideoSystemUiController
    implements MobileVideoSystemUiController {
  final calls = <String>[];

  @override
  Future<void> enter() async => calls.add('enter');

  @override
  Future<void> restore() async => calls.add('restore');
}
