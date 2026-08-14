/// 平台 bindings 与全屏/移动系统 UI 窄端口。
///
/// media presentation 拥有这些窄端口：Windows app/platform adapter 实现
/// [VideoFullscreenController]，Android adapter 实现 [MobileVideoSystemUiController]。
/// 页面一次生命周期只创建一种 bindings（Android 建 Mobile、Windows 建 Desktop），
/// 两个 controller 不同时存活。bindings 不进入 URL、route state 或 Provider state。
library;

/// 原生全屏窄端口：Windows 播放器窗口会话。
///
/// 表达会话初始化、实际/期望全屏查询、切换、退出与恢复释放。把插件失败转换
/// 为安全结果，不把平台异常泄漏到 Widget。由 app/platform adapter 实现。
abstract interface class VideoFullscreenController {
  /// 平台已确认的实际全屏状态（含外部窗口事件校准）。
  bool get actualFullscreen;

  /// 输入已请求、尚未确认的期望全屏状态。
  bool get desiredFullscreen;

  /// 开始一次播放器窗口会话并记录初始状态；不改变窗口状态。
  Future<void> initializeSession();

  /// 切换期望全屏状态，收敛到最终 desired；返回是否被消费与是否成功。
  Future<VideoFullscreenCommandResult> toggle();

  /// 当前或期望为全屏时退出；窗口模式时返回 consumed=false 的成功结果。
  Future<VideoFullscreenCommandResult> exitIfFullscreen();

  /// 恢复会话初始状态并释放；重复到达必须幂等。
  Future<bool> restoreAndDispose();
}

/// 全屏命令结果：区分是否被消费与是否成功。
final class VideoFullscreenCommandResult {
  const VideoFullscreenCommandResult({
    required this.consumed,
    required this.succeeded,
  });

  final bool consumed;
  final bool succeeded;
}

/// Android 沉浸式系统 UI 窄端口：进入与恢复。
abstract interface class MobileVideoSystemUiController {
  Future<void> enter();
  Future<void> restore();
}

/// 页面级平台 bindings 基类：sealed，只能派生 Mobile/Desktop 两种。
sealed class VideoPlayerPlatformBindings {
  const VideoPlayerPlatformBindings();
}

/// Android 平台 bindings：携带移动系统 UI 控制器。
final class MobileVideoPlayerBindings extends VideoPlayerPlatformBindings {
  const MobileVideoPlayerBindings({required this.systemUi});

  final MobileVideoSystemUiController systemUi;
}

/// Windows 平台 bindings：携带原生全屏控制器。
final class DesktopVideoPlayerBindings extends VideoPlayerPlatformBindings {
  const DesktopVideoPlayerBindings({required this.fullscreen});

  final VideoFullscreenController fullscreen;
}

/// 页面级 bindings 工厂：app composition 每次打开视频时调用一次，
/// 生成互不共享瞬态的 bindings；测试显式注入 Fake。
typedef VideoPlayerPlatformBindingsFactory =
    VideoPlayerPlatformBindings Function();
