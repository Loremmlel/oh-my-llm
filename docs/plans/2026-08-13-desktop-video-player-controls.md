# Windows Desktop Video Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Android 触摸播放器行为和现有控制栏布局的前提下，为 Windows 建立完整的桌面键鼠操控、真正的原生全屏，并把播放能力与平台输入状态彻底分离。

**Architecture:** `VideoPlaybackController` 独占 `VideoPlayerController`、共享播放状态和跨平台命令；`MobileVideoInteractionController` 与 `DesktopVideoInteractionController` 只把平台输入翻译为共享命令。app composition 为每个播放器页面注入 Mobile/Desktop bindings，Windows 全屏通过 presentation-owned 窄端口连接 `window_manager` adapter，Android 沉浸式与方向操作通过独立 SystemChrome adapter 保持等价。

**Tech Stack:** Flutter 3.44.6 / Dart 3.11.5 / Riverpod 3.4.2 / GoRouter 17.4.0 / `video_player` 2.13.0 / `video_player_win` 3.2.2 / `window_manager` 0.5.0 / Flutter HardwareKeyboard `KeyDownEvent` + `KeyRepeatEvent` + `KeyUpEvent` / WidgetTester。

## Global Constraints

- 批准设计是 `docs/specs/2026-08-13-desktop-video-player-controls-design.md`；任何实现与设计冲突时立即停止，先修订设计/计划，不凭实现者偏好猜测。
- 当前实现基线是 commit `0a2c33cf9e24bb27625cbcbbe409b3a57c74b41a`，版本 `3.45.2+0`；执行前重新检查 `git status --short` 和 `git log -1`，不得覆盖后续用户改动。
- 本计划文件在撰写阶段不自动提交；执行者必须从所有功能提交的 `git add` 路径中排除它，除非用户另行明确授权提交计划。
- Windows 始终采用 Desktop bindings；即使存在触摸屏也不安装 Android 双击 Seek、画面长按或横拖 Seek。
- Android 保持单击切换控制栏、双击 ±15 秒、画面长按临时 3 倍速、横拖预览/松手单次 Seek、系统边缘取消和既有外接键盘 ±15 秒行为。
- Windows 键盘契约固定：`←` down 快退 5 秒且 repeat 无副作用；`→` 在 400ms 前 KeyUp 快进 5 秒，达到 400ms 后只临时 3 倍速；`↑/↓` 每个 down/repeat 调音 5%；`M` 静音恢复；`F` 原生全屏；`Escape` 弹层→退出全屏→关闭页面。
- Windows 鼠标契约固定：单击播放/暂停；双击仅切换全屏；鼠标活动显示控制栏/光标；播放中静止 3 秒隐藏；垂直滚轮每个被接受事件调音 5%，50ms leading-edge 节流；水平滚动忽略。
- 不新增常驻倍速快捷键、快捷键设置、播放列表、字幕、逐帧、画面缩放或动态触摸/鼠标模式切换。
- 不修改控制栏布局、媒体资源模型、媒体 route query、Sync 协议、`MediaLibrary` 或播放器引擎选择。
- `VideoPlaybackController` 是修改底层 `VideoPlayerController` 的唯一 owner；页面只可读取 controller 以构建 `VideoPlayer` Widget，Mobile/Desktop controller 不得直接调用底层播放器。
- 平台选择只发生在 `lib/app/` composition/router；不得从 `LocalMediaResource`/`NetworkMediaResource` 推断平台，不得在 media application/domain 中出现平台输入分支。
- `window_manager: ^0.5.0` 是本次唯一允许新增的生产依赖；插件只出现在 app/platform adapter 与 bootstrap 初始化路径。
- Flutter 版本保持 3.44.x stable（CI 3.44.6），Dart SDK 保持 `^3.11.5`；不得顺带升级其他依赖。
- 所有生产注释和测试名称使用简体中文；不得写任务号、审查编号或阶段编号到生产代码/测试名称。
- 不使用 `part`/`part of`；跨 `app/core/feature` 引用使用 `package:oh_my_llm/...`，media feature 内部使用相对 import。
- 测试等待初始化计数、Focus、受控 Timer、窗口 gateway call history 等可观察信号；不得新增真实 `Future.delayed`、任意固定 flush 或通用 `pumpAndSettle()`。
- 每个任务严格执行 red → green；Flutter 测试、analyze 和 build 输出写入 ignored 的 `logs/`，红绿证据分别用 `logs/desktop-video-taskN-red.log` / `logs/desktop-video-taskN-green.log`。
- 每个提交前对本任务所有 Dart 文件运行 `dart format`，暂存后运行 `dart format --output=none --set-exit-if-changed`；非零不得提交。
- commit subject/body 使用简体中文，保留英文 conventional prefix；post-commit hook 会自动 amend 版本，提交后重新读取最终 HEAD、版本和工作区。
- 重型 Flutter/Dart 门禁串行执行；`flutter analyze` 若依赖解析后停滞，按仓库规则改跑 `flutter analyze --no-pub`。
- Windows/Android 手工 smoke 未执行时必须逐项标记 `pending`；自动测试、analyze 或 build 不能代替真实窗口、键盘、鼠标和设备验证。
- 本计划不授权 push、PR、force、删除用户媒体文件或修改真实媒体数据。

---

## 1. File and Contract Map

### 1.1 Verified existing files

以下路径已在 `0a2c33c` 上核对：

| File | Baseline responsibility | Planned responsibility |
|---|---|---|
| `lib/features/media/presentation/pages/video_player_state.dart` | 共享播放状态与移动手势字段混合 | 被聚焦的共享 state/feedback 文件替代并删除 |
| `lib/features/media/presentation/pages/video_player_gesture.dart` | 生命周期、播放命令、Mobile 手势混合 | 拆成共享核心与 Mobile interaction 后删除 |
| `lib/features/media/presentation/pages/video_player_page.dart` | 无条件 Mobile 手势、SystemChrome、局部键盘 | 只做页面组合、Focus、平台事件转发和关闭顺序 |
| `lib/features/media/presentation/widgets/video_player_controls.dart` | 固定 15 秒/3 倍速中央枚举与现有控制栏 | 保持布局，消费结构化动态反馈 |
| `lib/features/media/presentation/pages/media_route_pages.dart` | 解析资源并创建 `VideoPlayerPage` | 透传 app composition 的 bindings factory |
| `lib/features/media/presentation/pages/media_video_controller_factory.dart` | local/network controller factory | 保持不变，由共享核心消费 |
| `lib/app/router/app_router.dart` | 创建媒体子路由 | 注入页面级平台 bindings factory |
| `lib/bootstrap.dart` | prefs→DB→logger→runApp | Windows 生产路径额外初始化 window runtime，测试可注入 host platform 与 no-op |
| `pubspec.yaml` / `pubspec.lock` | 当前依赖 | 添加并锁定 `window_manager: ^0.5.0` |
| `windows/flutter/generated_plugin_registrant.cc` | Windows 插件注册 | 接受 Flutter 生成的 window_manager 注册 |
| `windows/flutter/generated_plugins.cmake` | Windows 插件 CMake 列表 | 接受 Flutter 生成的 window_manager 条目 |
| `AGENTS.md:143-151` | bootstrap 三注入参数与固定启动顺序 | 记录 window initializer 注入与 Windows-only 顺序 |
| `docs/视频局域网广播-prd.md:489-735,1285-1440` | 把 Mobile 手势描述为通用播放器行为 | 补充当前 Android/Windows 分平台操控契约 |
| `README.md:258` 附近媒体说明 | 仅概述视频播放器 | 简述 Windows 桌面快捷键与 Android 手势分工 |

### 1.2 Planned production files

| File | Single responsibility |
|---|---|
| `lib/features/media/presentation/pages/video_playback_state.dart` | 共享不可变 UI 状态与结构化中央反馈 |
| `lib/features/media/presentation/pages/video_playback_controller.dart` | 底层播放器生命周期、共享命令唯一 owner 与不可伪造 temporary-speed lease token |
| `lib/features/media/presentation/pages/mobile_video_interaction_controller.dart` | Android tap/double-tap/long-press/horizontal-drag 与外接键盘映射 |
| `lib/features/media/presentation/pages/desktop_video_interaction_controller.dart` | Windows key down/repeat/up、右键 400ms 状态机、鼠标活动/滚轮状态 |
| `lib/features/media/presentation/pages/video_player_platform_bindings.dart` | Mobile/Desktop sealed bindings、全屏/SystemChrome 窄端口与 factories |
| `lib/app/platform/windows_video_fullscreen_controller.dart` | window_manager gateway、actual/desired 串行队列与会话恢复 |
| `lib/app/platform/android_video_system_ui_controller.dart` | Android immersive/orientation enter/restore |
| `lib/app/composition/video_player_platform_bindings_factory.dart` | 唯一 TargetPlatform→bindings 选择点 |

### 1.3 Planned tests and helpers

| File | Contract |
|---|---|
| `test/features/media/presentation/pages/video_playback_controller_test.dart` | init/play/seek/feedback/speed lease/audio/mute/lifecycle |
| `test/features/media/presentation/pages/mobile_video_interaction_controller_test.dart` | Android 15 秒、长按、drag commit/cancel |
| `test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart` | 5 秒、400ms、repeat、focus/blur、M/F/Escape |
| `test/features/media/presentation/pages/video_player_desktop_test.dart` | Desktop page focus、mouse、cursor、scroll、fullscreen/route behavior |
| `test/features/media/helpers/fake_video_player_platform_bindings.dart` | Fake fullscreen/SystemChrome ports and factories |
| `test/app/platform/windows_video_fullscreen_controller_test.dart` | window actual/desired queue, events, failure, restore |
| `test/app/composition/video_player_platform_bindings_factory_test.dart` | Windows/Desktop 与 Android/Mobile 唯一选择 |
| existing `video_player_page_test.dart` | 保留页面生命周期与 Android pointer 行为，迁移重复 controller 断言 |
| existing `video_player_accessibility_test.dart` | 平台化 semantics/hints/focus/keyboard/live region |
| existing `media_route_pages_test.dart` | bindings factory 透传与资源行为不变 |
| existing `bootstrap_integration_test.dart` | injected Windows initializer，不调用真实 plugin |
| existing `app_router_test.dart` | router 工厂注入与 route matrix 不变 |

### 1.4 Locked interfaces

实现期间允许补充私有 helper，但以下 public/跨文件名字与方向固定：

```dart
sealed class VideoCenterFeedback {
  const VideoCenterFeedback();
}

final class VideoRelativeSeekFeedback extends VideoCenterFeedback {
  const VideoRelativeSeekFeedback({required this.delta, required this.target});
  final Duration delta;
  final Duration target;
}

final class VideoSeekPreviewFeedback extends VideoCenterFeedback {
  const VideoSeekPreviewFeedback(this.target);
  final Duration target;
}

final class VideoTemporarySpeedFeedback extends VideoCenterFeedback {
  const VideoTemporarySpeedFeedback(this.speed);
  final double speed;
}

final class VideoVolumeFeedback extends VideoCenterFeedback {
  const VideoVolumeFeedback({required this.volume, required this.isMuted});
  final double volume;
  final bool isMuted;
}

final class VideoOperationFailureFeedback extends VideoCenterFeedback {
  const VideoOperationFailureFeedback(this.message);
  final String message;
}

final class VideoTemporarySpeedLease {
  const VideoTemporarySpeedLease._(this.id);
  final int id;
}

abstract interface class VideoFullscreenController {
  bool get actualFullscreen;
  bool get desiredFullscreen;
  Future<void> initializeSession();
  Future<VideoFullscreenCommandResult> toggle();
  Future<VideoFullscreenCommandResult> exitIfFullscreen();
  Future<bool> restoreAndDispose();
}

final class VideoFullscreenCommandResult {
  const VideoFullscreenCommandResult({
    required this.consumed,
    required this.succeeded,
  });
  final bool consumed;
  final bool succeeded;
}

abstract interface class MobileVideoSystemUiController {
  Future<void> enter();
  Future<void> restore();
}

sealed class VideoPlayerPlatformBindings {
  const VideoPlayerPlatformBindings();
}

final class MobileVideoPlayerBindings extends VideoPlayerPlatformBindings {
  const MobileVideoPlayerBindings({required this.systemUi});
  final MobileVideoSystemUiController systemUi;
}

final class DesktopVideoPlayerBindings extends VideoPlayerPlatformBindings {
  const DesktopVideoPlayerBindings({required this.fullscreen});
  final VideoFullscreenController fullscreen;
}

typedef VideoPlayerPlatformBindingsFactory =
    VideoPlayerPlatformBindings Function();
```

`VideoTemporarySpeedLease` 必须定义在 `video_playback_controller.dart`，与创建它的 controller 处于同一 Dart library；禁止为了跨文件访问私有构造器改成 public constructor，也禁止使用 `part`。

`VideoPlaybackController` 的跨文件命令固定为：

```dart
Future<void> initialize();
Future<void> retry();
void togglePlayPause();
void seekRelative(Duration offset);
void setPersistentSpeed(double speed);
VideoTemporarySpeedLease? beginTemporarySpeed(double speed);
void endTemporarySpeed(VideoTemporarySpeedLease lease);
void setVolume(double volume);
void adjustVolume(double delta);
void toggleMute();
void onSeekStart(double fraction);
void onSeekUpdate(double fraction);
void onSeekEnd();
void onSeekCancel();
void showControls();
void toggleControls();
void holdControlsVisible();
void releaseControlsHold();
void showOperationFailure(String message);
void onAppLifecyclePaused();
void dispose();
```

---

### Task 1: Extract the shared playback core and Mobile interaction

**Files:**
- Create: `lib/features/media/presentation/pages/video_playback_state.dart`
- Create: `lib/features/media/presentation/pages/video_playback_controller.dart`
- Create: `lib/features/media/presentation/pages/mobile_video_interaction_controller.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `lib/features/media/presentation/widgets/video_player_controls.dart`
- Delete: `lib/features/media/presentation/pages/video_player_state.dart`
- Delete: `lib/features/media/presentation/pages/video_player_gesture.dart`
- Create: `test/features/media/presentation/pages/video_playback_controller_test.dart`
- Create: `test/features/media/presentation/pages/mobile_video_interaction_controller_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_page_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_accessibility_test.dart`
- Modify: `test/features/media/helpers/fake_video_player_controller.dart`

**Interfaces:**
- Consumes: `MediaResource`, `MediaVideoControllerFactory`, existing `VideoPlayerController` fake and current Mobile behavior tests.
- Produces: `VideoPlaybackState`, `VideoPlaybackController`, `VideoCenterFeedback` hierarchy, lease-based temporary speed, `MobileVideoInteractionController`, `CancelAwareHorizontalDragRecognizer` in Mobile-only code.

- [ ] **Step 1: Record the clean baseline and run current player tests**

```powershell
git status --short
git log -1 --oneline
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task1-baseline.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task1-baseline.log
```

Expected: `EXIT=0`; `git status` 只允许出现本计划文件。若 baseline 失败，先诊断现状，不开始重构。

- [ ] **Step 2: Write failing shared-core tests**

在新测试中建立 `_createController(fake)` helper，传入同一个 Fake factory，并添加以下中文用例：

```dart
testWidgets('初始化后自动播放并投影时长位置与缓冲状态', (tester) async {
  final fake = FakeVideoPlayerController()
    ..fakePosition = const Duration(seconds: 30)
    ..fakeDuration = const Duration(minutes: 5);
  final controller = createPlaybackController(fake);
  addTearDown(controller.dispose);

  await controller.initialize();

  expect(controller.state.isInitialized, isTrue);
  expect(controller.state.isPlaying, isTrue);
  expect(controller.state.currentPosition, const Duration(seconds: 30));
  expect(fake.playCallCount, 1);
});

testWidgets('相对 Seek 使用最新位置并在首尾边界 clamp', (tester) async {
  final fake = FakeVideoPlayerController()
    ..fakePosition = const Duration(seconds: 2);
  final controller = createPlaybackController(fake);
  addTearDown(controller.dispose);
  await controller.initialize();
  fake.seekToCalls.clear();

  controller.seekRelative(const Duration(seconds: -5));
  expect(fake.seekToCalls.last, Duration.zero);
  expect(
    controller.state.centerFeedback,
    isA<VideoRelativeSeekFeedback>()
        .having((value) => value.delta, 'delta', const Duration(seconds: -5))
        .having((value) => value.target, 'target', Duration.zero),
  );
});

testWidgets('错误 lease 不能结束当前临时倍速且常驻倍速更新后再恢复',
    (tester) async {
  final fake = FakeVideoPlayerController();
  final controller = createPlaybackController(fake);
  addTearDown(controller.dispose);
  await controller.initialize();

  final stale = controller.beginTemporarySpeed(3.0)!;
  controller.endTemporarySpeed(stale);
  final active = controller.beginTemporarySpeed(3.0)!;
  controller.setPersistentSpeed(1.5);
  controller.endTemporarySpeed(stale);
  expect(fake.fakePlaybackSpeed, 3.0);

  controller.endTemporarySpeed(active);
  expect(fake.fakePlaybackSpeed, 1.5);
});
```

测试只用公开 lease API 构造 stale lease；禁止为测试暴露 lease constructor 或 `debugCreate...` 生产入口。

- [ ] **Step 3: Run the new tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task1-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/desktop-video-task1-red.log
```

Expected: non-zero，失败原因是新文件/API 尚不存在；不得接受环境插件错误作为 red 证据。

- [ ] **Step 4: Implement the shared state and feedback types**

`VideoPlaybackState` 是不可变投影；Timer、generation、active lease 等可变生命周期资源只保存在 controller 私有字段中。Mobile/Desktop 只读取 `controller.state`，不能改 state：

```dart
final class VideoPlaybackState {
  const VideoPlaybackState({
    this.controller,
    this.isInitialized = false,
    this.hasError = false,
    this.errorMessage,
    this.controlsVisible = true,
    this.isPlaying = false,
    this.hasEnded = false,
    this.isDragging = false,
    this.dragPositionMs = 0,
    this.bufferedPercent = 0,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.persistentSpeed = 1.0,
    this.effectiveSpeed = 1.0,
    this.volume = 1.0,
    this.lastNonZeroVolume = 1.0,
    this.isMuted = false,
    this.centerFeedback,
  });

  final VideoPlayerController? controller;
  final bool isInitialized;
  final bool hasError;
  final String? errorMessage;
  final bool controlsVisible;
  final bool isPlaying;
  final bool hasEnded;
  final bool isDragging;
  final double dragPositionMs;
  final double bufferedPercent;
  final Duration currentPosition;
  final Duration totalDuration;
  final double persistentSpeed;
  final double effectiveSpeed;
  final double volume;
  final double lastNonZeroVolume;
  final bool isMuted;
  final VideoCenterFeedback? centerFeedback;

  VideoPlaybackState copyWith({
    Object? controller = _unset,
    bool? isInitialized,
    bool? hasError,
    Object? errorMessage = _unset,
    bool? controlsVisible,
    bool? isPlaying,
    bool? hasEnded,
    bool? isDragging,
    double? dragPositionMs,
    double? bufferedPercent,
    Duration? currentPosition,
    Duration? totalDuration,
    double? persistentSpeed,
    double? effectiveSpeed,
    double? volume,
    double? lastNonZeroVolume,
    bool? isMuted,
    Object? centerFeedback = _unset,
  });
}
```

文件顶部定义 `const Object _unset = Object();`。`copyWith` 对 `controller`、`errorMessage` 与 `centerFeedback` 使用该私有 sentinel，以支持显式清空 nullable 字段；实现中先用 `identical(value, _unset)` 分支，再做目标 nullable 类型 cast，不得用 `value ?? oldValue` 导致 controller/错误/提示无法清除。controller 通过 `_emit(state.copyWith(...))` 单点替换 state 并调用 `onStateChanged`。

把固定 `CenterHintType` 替换为 File Map 中的 feedback hierarchy。`VideoCenterHint` 通过 exhaustive switch 读取实际 delta/target/speed/volume；Seek label 使用 `delta.abs().inSeconds`，不得继续写死 `15s`。

- [ ] **Step 5: Implement `VideoPlaybackController` as the only player owner**

构造函数和生命周期固定为：

```dart
VideoPlaybackController({
  required MediaResource resource,
  required MediaVideoControllerFactory controllerFactory,
  required VoidCallback onStateChanged,
}) : _resource = resource,
     _controllerFactory = controllerFactory,
     _onStateChanged = onStateChanged;

Future<void> initialize() => _replaceController();
Future<void> retry() => _replaceController();
```

`_replaceController()` 先增加 generation、清理 lease/timers/listener、dispose 旧 controller，再创建新 controller。`await initialize()` 后同时检查 `_disposed`、generation 和 controller identity；旧 Future 不得覆盖新状态。

把现有以下逻辑等价搬入共享核心：初始化/错误、controller listener、结束检测、播放暂停、相对 Seek、Slider Seek、控制栏三秒计时、feedback 一秒计时、生命周期暂停和 dispose。所有 `setPlaybackSpeed`、`setVolume`、`seekTo`、`play`、`pause` 调用只能存在于该文件。

临时倍速使用单 active lease：

```dart
VideoTemporarySpeedLease? beginTemporarySpeed(double speed) {
  if (!state.isInitialized || !state.isPlaying || state.hasEnded) return null;
  if (_activeSpeedLease != null) return null;
  final lease = VideoTemporarySpeedLease._(++_nextLeaseId);
  _activeSpeedLease = lease;
  _emit(state.copyWith(effectiveSpeed: speed));
  _controller?.setPlaybackSpeed(speed);
  _showFeedback(VideoTemporarySpeedFeedback(speed), autoHide: false);
  return lease;
}

void endTemporarySpeed(VideoTemporarySpeedLease lease) {
  if (!identical(_activeSpeedLease, lease)) return;
  _activeSpeedLease = null;
  _emit(state.copyWith(effectiveSpeed: state.persistentSpeed));
  _controller?.setPlaybackSpeed(state.persistentSpeed);
  _clearFeedback();
}
```

lease equality 不基于整数值重载；只接受 controller 返回的同一实例。

- [ ] **Step 6: Extract `MobileVideoInteractionController`**

Mobile 私有 state 包含：tap x、screen width、long-press lease、horizontal drag start/current、gesture 前 controlsVisible。公开方法保持页面可直接转发 Flutter details：

```dart
void handleTap();
void handleDoubleTapDown(TapDownDetails details);
void handleDoubleTap();
void handleLongPressStart(LongPressStartDetails details);
void handleLongPressEnd(LongPressEndDetails details);
void handleLongPressCancel();
void handleHorizontalDragStart(DragStartDetails details);
void handleHorizontalDragUpdate(DragUpdateDetails details);
void handleHorizontalDragEnd(DragEndDetails details);
void handleHorizontalDragCancel();
KeyEventResult handleSurfaceKey(KeyEvent event);
void dispose();
```

双击调用 `seekRelative(Duration(seconds: isLeft ? -15 : 15))`；长按保存 core 返回的 lease；横拖只通过 core 的 preview/commit/cancel API。把 `CancelAwareHorizontalDragRecognizer` 与说明移入该文件。

- [ ] **Step 7: Rewire the page without changing product behavior**

本任务结束时页面仍暂时只构建 Mobile interaction，确保中间提交不改变 Windows 当前行为。页面创建 core + Mobile，所有现有回调改为委托；页面不再直接调用 controller methods。

保留现有 Focus/Semantics、SystemChrome 和 RawGestureDetector 结构到后续平台绑定任务；这里只完成 owner 替换。删除两个旧文件，禁止保留兼容 wrapper 或第二套 state。

- [ ] **Step 8: Write and run Mobile controller regression tests**

添加参数化用例：

```dart
final seekCases = [
  (x: 100.0, width: 400.0, expected: const Duration(seconds: -15)),
  (x: 300.0, width: 400.0, expected: const Duration(seconds: 15)),
];

for (final testCase in seekCases) {
  testWidgets('双击左右半屏继续按 15 秒调用共享 Seek', (tester) async {
    final harness = await createMobileHarness();
    harness.interaction.updateScreenWidth(testCase.width);
    harness.interaction.handleDoubleTapDown(
      TapDownDetails(globalPosition: Offset(testCase.x, 100)),
    );
    harness.interaction.handleDoubleTap();
    expect(harness.fake.seekToCalls.last,
        const Duration(seconds: 30) + testCase.expected);
  });
}
```

另测：长按 pause/ended 无 lease；松开恢复最新常驻倍速；drag update 不 seek、end 一次 seek、cancel 零 seek；取消标志不污染下一次 drag。

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_playback_controller_test.dart test/features/media/presentation/pages/mobile_video_interaction_controller_test.dart test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task1-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task1-green.log
```

Expected: `EXIT=0`; Android-visible tap/double/long/drag behavior and current a11y tests remain green。

- [ ] **Step 9: Audit ownership, format and commit**

```powershell
rg -n "\.seekTo\(|\.setVolume\(|\.setPlaybackSpeed\(|\.play\(|\.pause\(" lib/features/media/presentation/pages
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
$StagePaths = @(
  'lib/features/media/presentation/pages/video_playback_state.dart',
  'lib/features/media/presentation/pages/video_playback_controller.dart',
  'lib/features/media/presentation/pages/mobile_video_interaction_controller.dart',
  'lib/features/media/presentation/pages/video_player_page.dart',
  'lib/features/media/presentation/pages/video_player_state.dart',
  'lib/features/media/presentation/pages/video_player_gesture.dart',
  'lib/features/media/presentation/widgets/video_player_controls.dart',
  'test/features/media/presentation/pages/video_playback_controller_test.dart',
  'test/features/media/presentation/pages/mobile_video_interaction_controller_test.dart',
  'test/features/media/presentation/pages/video_player_page_test.dart',
  'test/features/media/presentation/pages/video_player_accessibility_test.dart',
  'test/features/media/helpers/fake_video_player_controller.dart'
)
git add -- $StagePaths
git diff --cached --check
git commit -m "refactor(media): 分离视频播放核心与移动端输入"
git status --short
git log -1 --oneline
```

Expected: controller mutation 命中只在 `video_playback_controller.dart`（测试 fake 除外）；提交不包含本计划；hook 后只剩计划文件未提交。

---

### Task 2: Implement shared volume, mute and dynamic feedback contracts

**Files:**
- Modify: `lib/features/media/presentation/pages/video_playback_state.dart`
- Modify: `lib/features/media/presentation/pages/video_playback_controller.dart`
- Modify: `lib/features/media/presentation/widgets/video_player_controls.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `test/features/media/presentation/pages/video_playback_controller_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_accessibility_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_page_test.dart`

**Interfaces:**
- Consumes: Task 1 shared core, `VideoVolumeFeedback`, existing top-bar volume Slider.
- Produces: exact `setVolume`/`adjustVolume`/`toggleMute` semantics, dynamic Seek/speed/volume/failure feedback rendering and Semantics.

- [ ] **Step 1: Write the full failing audio matrix**

用一个参数化测试覆盖普通步进边界：

```dart
final cases = [
  (start: 0.98, delta: 0.05, expected: 1.0),
  (start: 0.02, delta: -0.05, expected: 0.0),
  (start: 0.50, delta: 0.05, expected: 0.55),
];
```

再添加独立契约测试：

```dart
testWidgets('M 静音后再次切换恢复最后非零音量', (tester) async {
  final harness = await createPlaybackHarness(initialVolume: 0.65);
  harness.controller.toggleMute();
  expect(harness.controller.state.isMuted, isTrue);
  expect(harness.fake.setVolumeCalls.last, 0.0);

  harness.controller.toggleMute();
  expect(harness.controller.state.isMuted, isFalse);
  expect(harness.fake.setVolumeCalls.last, 0.65);
});

testWidgets('显式静音时调音先恢复记忆音量再应用步进', (tester) async {
  final harness = await createPlaybackHarness(initialVolume: 0.60);
  harness.controller.toggleMute();
  harness.controller.adjustVolume(-0.05);
  expect(harness.controller.state.isMuted, isFalse);
  expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
});

testWidgets('手动零音量不覆盖记忆且上调从百分之五开始', (tester) async {
  final harness = await createPlaybackHarness(initialVolume: 0.60);
  harness.controller.setVolume(0);
  expect(harness.controller.state.lastNonZeroVolume, 0.60);
  expect(harness.controller.state.isMuted, isFalse);
  harness.controller.adjustVolume(0.05);
  expect(harness.fake.setVolumeCalls.last, 0.05);
});
```

- [ ] **Step 2: Run audio tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_playback_controller_test.dart --plain-name "M 静音后再次切换恢复最后非零音量" --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task2-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 100 logs/desktop-video-task2-red.log
```

Expected: non-zero，因为 Task 1 尚未实现完整显式静音/恢复契约。

- [ ] **Step 3: Implement exact audio state transitions**

```dart
void setVolume(double value) {
  final next = value.clamp(0.0, 1.0);
  _applyVolume(next, isMuted: false);
}

void adjustVolume(double delta) {
  final base = state.isMuted ? state.lastNonZeroVolume : state.volume;
  _applyVolume((base + delta).clamp(0.0, 1.0), isMuted: false);
}

void toggleMute() {
  if (state.isMuted || state.volume <= 0.0) {
    _applyVolume(state.lastNonZeroVolume, isMuted: false);
    return;
  }
  _applyVolume(
    0.0,
    isMuted: true,
    rememberedVolume: state.volume,
  );
}
```

`_applyVolume(double value, {required bool isMuted, double? rememberedVolume})` 用一次 `copyWith` 写入新 volume/mute/lastNonZero，再通知 UI；只在新值与当前底层值差异大于 `0.0001` 时调用 `setVolume`。`rememberedVolume` 优先，否则大于零的新值更新 lastNonZero；每次成功命令创建 `VideoVolumeFeedback`。初始化从 controller value 投影真实 volume，若为零则保留默认 lastNonZero=1.0。

- [ ] **Step 4: Render dynamic feedback without layout changes**

移除所有固定 `15s`/`3.0x` 枚举分支。保持现有容器 padding、圆角、颜色和位置，只替换 content/semantics switch：

```dart
final semanticsLabel = switch (feedback) {
  VideoRelativeSeekFeedback(:final delta) =>
    delta.isNegative
        ? '已快退 ${delta.abs().inSeconds} 秒'
        : '已快进 ${delta.inSeconds} 秒',
  VideoSeekPreviewFeedback(:final target) =>
    '预览位置 ${formatVideoDuration(target)}',
  VideoTemporarySpeedFeedback(:final speed) =>
    '临时 ${speed.toStringAsFixed(1)} 倍速播放',
  VideoVolumeFeedback(isMuted: true) => '已静音',
  VideoVolumeFeedback(:final volume) =>
    '音量 ${(volume * 100).round()}%',
  VideoOperationFailureFeedback(:final message) => message,
};
```

Seek、temporary speed、mute/failure 是离散 live region；Seek preview 不 live；连续 volume 只更新同一节点。

- [ ] **Step 5: Strengthen Widget and Semantics tests**

现有 Android case 继续断言 15 秒。新增直接向 core 发送 5 秒后 UI/semantics 显示 5 秒的 case，证明 Widget 不写死平台值；新增 65%/静音/恢复 tooltip 与单一 live-region case。不得通过查找私有 feedback Widget 类型代替可见文本/语义。

- [ ] **Step 6: Run green, format and commit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_playback_controller_test.dart test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task2-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task2-green.log
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
git add -- lib/features/media/presentation/pages/video_playback_state.dart lib/features/media/presentation/pages/video_playback_controller.dart lib/features/media/presentation/widgets/video_player_controls.dart lib/features/media/presentation/pages/video_player_page.dart test/features/media/presentation/pages/video_playback_controller_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart test/features/media/presentation/pages/video_player_page_test.dart
git diff --cached --check
git commit -m "feat(media): 统一视频音量静音与动态提示"
git status --short
```

Expected: `EXIT=0`；commit 只包含共享音量/反馈行为，不含 Desktop 输入或 window plugin。

---

### Task 3: Build the Desktop keyboard controller and platform ports

**Files:**
- Create: `lib/features/media/presentation/pages/video_player_platform_bindings.dart`
- Create: `lib/features/media/presentation/pages/desktop_video_interaction_controller.dart`
- Create: `test/features/media/helpers/fake_video_player_platform_bindings.dart`
- Create: `test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart`
- Modify: `test/features/media/presentation/pages/video_playback_controller_test.dart`

**Interfaces:**
- Consumes: Task 1/2 `VideoPlaybackController`, locked bindings/fullscreen interfaces, Flutter `KeyEvent` model.
- Produces: deterministic Desktop key state machine, Fake fullscreen/SystemUI ports for later Widget/composition tasks. This task does not yet activate Desktop in production routes.

- [ ] **Step 1: Create Fake ports and write right-arrow red tests**

Fake fullscreen controller must record exact call order and allow deterministic failure:

```dart
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
```

在 `testWidgets` fake-clock zone 中添加：

```dart
testWidgets('右方向键四百毫秒前松开只快进五秒', (tester) async {
  final harness = await createDesktopHarness();
  harness.keyDown(LogicalKeyboardKey.arrowRight);
  expect(harness.fake.seekToCalls, isEmpty);

  await tester.pump(const Duration(milliseconds: 399));
  harness.keyUp(LogicalKeyboardKey.arrowRight);

  expect(harness.fake.seekToCalls, [const Duration(seconds: 35)]);
  expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
});

testWidgets('右方向键达到四百毫秒只临时三倍速且松开恢复', (tester) async {
  final harness = await createDesktopHarness();
  harness.keyDown(LogicalKeyboardKey.arrowRight);
  await tester.pump(const Duration(milliseconds: 400));

  expect(harness.fake.seekToCalls, isEmpty);
  expect(harness.fake.setPlaybackSpeedCalls, [3.0]);

  harness.keyUp(LogicalKeyboardKey.arrowRight);
  expect(harness.fake.seekToCalls, isEmpty);
  expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
});
```

- [ ] **Step 2: Add the remaining failing keyboard matrix**

逐项添加中文 case：

- 右键 repeat 不改变 pending/longHold；
- 暂停、ended、error 达到 400ms 不加速且 KeyUp 不补 Seek；
- 表面失焦、window blur、retry/dispose 取消 pending/hold，迟到 KeyUp 无副作用；
- 左键 down 立即 -5 秒，两个 repeat 都不再 Seek；
- 上下 down/repeat 每个 ±5%，KeyUp 无副作用；
- Space/mediaPlayPause/M/F 的 repeat 无副作用；
- M/F/FullScreen failure 分别调用共享 core/fake port；
- Escape 在 fullscreen 时 consumed 且不请求 close，windowed 时请求一次 close。

用 `KeyEventSimulator.simulateKeyRepeatEvent` 或直接构造 `KeyRepeatEvent`，不得用多次 `sendKeyDownEvent` 冒充 repeat。

- [ ] **Step 3: Run Desktop controller tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task3-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/desktop-video-task3-red.log
```

Expected: non-zero，新 controller/bindings 尚不存在。

- [ ] **Step 4: Implement sealed bindings and exact controller constructor**

除 File Map 锁定类型外，Desktop constructor 固定为：

```dart
DesktopVideoInteractionController({
  required VideoPlaybackController playback,
  required VideoFullscreenController fullscreen,
  required Future<void> Function() onRequestClose,
  required VoidCallback onInteractionChanged,
  Timer Function(Duration, VoidCallback) timerFactory = Timer.new,
}) : _playback = playback,
     _fullscreen = fullscreen,
     _onRequestClose = onRequestClose,
     _onInteractionChanged = onInteractionChanged,
     _timerFactory = timerFactory;
```

公开入口：

```dart
KeyEventResult handleSurfaceKey(KeyEvent event);
KeyEventResult handlePageKey(KeyEvent event);
void onSurfaceFocusLost();
void onWindowBlur();
void onPlaybackEnded();
void cancelForRetry();
void dispose();
```

`handleSurfaceKey` 处理 Space/media/Enter/四方向键；`handlePageKey` 只处理 M/F/Escape。controller 不读取 `BuildContext`、`FocusNode` 或 Navigator。

- [ ] **Step 5: Implement the 400ms classifier**

```dart
void _onRightDown() {
  if (_rightPressed) return;
  _rightPressed = true;
  _rightClassifiedAsHold = false;
  _rightHoldTimer = _timerFactory(const Duration(milliseconds: 400), () {
    if (_disposed || !_rightPressed) return;
    _rightClassifiedAsHold = true;
    _rightSpeedLease = _playback.beginTemporarySpeed(3.0);
    _onInteractionChanged();
  });
}

void _onRightUp() {
  if (!_rightPressed) return;
  final seek = !_rightClassifiedAsHold;
  _cancelRightState();
  if (seek) _playback.seekRelative(const Duration(seconds: 5));
}

void _cancelRightState() {
  _rightHoldTimer?.cancel();
  _rightHoldTimer = null;
  _rightPressed = false;
  _rightClassifiedAsHold = false;
  final lease = _rightSpeedLease;
  _rightSpeedLease = null;
  if (lease != null) _playback.endTemporarySpeed(lease);
}
```

关键点：timer 到期即标记 hold，即使 `beginTemporarySpeed` 返回 null；因此暂停/ended 松开也不会补 Seek。focus lost/blur/retry/dispose 调用 `_cancelRightState`，且明确不执行短按分支。

- [ ] **Step 6: Implement all remaining key mappings**

使用 event type exhaustive branch：

```dart
if (event is KeyUpEvent) return _handleKeyUp(event.logicalKey);
if (event is KeyRepeatEvent) return _handleRepeat(event.logicalKey);
if (event is KeyDownEvent) return _handleKeyDown(event.logicalKey);
return KeyEventResult.ignored;
```

- Left down 调 `seekRelative(-5s)`，repeat 返回 handled 但无副作用；
- Up/down down+repeat 调 `adjustVolume(±0.05)`；
- Space/mediaPlayPause/Enter 只 down 生效；
- M down 调 `toggleMute()`；F down `unawaited(_toggleFullscreen())`；
- Escape down `unawaited(_exitFullscreenOrClose())`；全屏失败显示 `无法切换全屏` 且不 close；
- 所有已识别的 repeat/up 返回 handled，防止事件落到平台产生第二行为；未映射键 ignored。

- [ ] **Step 7: Run green, format and commit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart test/features/media/presentation/pages/video_playback_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task3-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task3-green.log
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
git add lib/features/media/presentation/pages/video_player_platform_bindings.dart lib/features/media/presentation/pages/desktop_video_interaction_controller.dart test/features/media/helpers/fake_video_player_platform_bindings.dart test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart test/features/media/presentation/pages/video_playback_controller_test.dart
git diff --cached --check
git commit -m "feat(media): 建立 Windows 视频键盘状态机"
git status --short
```

Expected: Desktop controller 可独立验证但生产页面尚未选择它；只有计划文件未提交。

---

### Task 4: Add the Windows fullscreen adapter and bootstrap runtime

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `windows/flutter/generated_plugin_registrant.cc`
- Modify: `windows/flutter/generated_plugins.cmake`
- Create: `lib/app/platform/windows_video_fullscreen_controller.dart`
- Modify: `lib/bootstrap.dart`
- Modify: `AGENTS.md:143-151`
- Create: `test/app/platform/windows_video_fullscreen_controller_test.dart`
- Modify: `test/integration/bootstrap_integration_test.dart`

**Interfaces:**
- Consumes: Task 3 `VideoFullscreenController`/result, `window_manager: ^0.5.0`.
- Produces: testable `WindowsVideoWindowGateway`, production `WindowManagerVideoWindowGateway`, sanitized error reporter, serialized `WindowsVideoFullscreenController`, Windows-only runtime initializer seam.

- [ ] **Step 1: Add dependency and regenerate plugin files**

```powershell
flutter pub add window_manager:^0.5.0
flutter pub get
git diff -- pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
```

Expected: only window_manager dependency graph/plugin registration changes；不得升级其他 direct dependencies。若 resolver 改写无关依赖，恢复无关升级并重跑 `flutter pub get`。

- [ ] **Step 2: Define the gateway and write queue tests red**

app-owned gateway：

```dart
abstract interface class WindowsVideoWindowGateway {
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool value);
  void addFullscreenListener(ValueChanged<bool> listener);
  void removeFullscreenListener(ValueChanged<bool> listener);
  void dispose();
}

typedef VideoWindowErrorReporter =
    void Function(String operation, Object error, StackTrace stackTrace);
```

Fake gateway 记录 `setCalls`，用 `Completer<void>? pendingSet` 控制在途命令，并提供 `emitFullscreen(bool)`。添加测试：

```dart
test('快速切换依据 desired 串行执行而不读取陈旧 actual', () async {
  final gateway = FakeWindowsVideoWindowGateway(initialFullscreen: false);
  final controller = WindowsVideoFullscreenController(gateway: gateway);
  await controller.initializeSession();

  gateway.blockNextSet();
  final first = controller.toggle();
  final second = controller.toggle();
  expect(gateway.setCalls, [true]);

  gateway.completeBlockedSet(actual: true);
  await first;
  await second;
  expect(gateway.setCalls, [true, false]);
  expect(controller.desiredFullscreen, isFalse);
});
```

再测：initial false/true 恢复；初始化查询异常不向页面抛出且后续命令返回 failed；失败 reporter 收到固定 operation 与 error type、但用户反馈不含异常文本；exit-if-windowed consumed false；外部 event 在无 command in-flight 时同时更新 actual/desired；命令回执只更新 actual；旧失败不覆盖更新 desired；restore/dispose 幂等。

- [ ] **Step 3: Run fullscreen tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/platform/windows_video_fullscreen_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task4-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/desktop-video-task4-red.log
```

Expected: non-zero，adapter/gateway 尚不存在。

- [ ] **Step 4: Implement production gateway without leaking plugin types**

`WindowManagerVideoWindowGateway with WindowListener` 注册/反注册自身，保存 presentation-neutral `ValueChanged<bool>` listeners：

```dart
@override
void onWindowEnterFullScreen() => _emit(true);

@override
void onWindowLeaveFullScreen() => _emit(false);

@override
Future<bool> isFullScreen() => windowManager.isFullScreen();

@override
Future<void> setFullScreen(bool value) =>
    windowManager.setFullScreen(value);
```

`dispose()` 幂等移除 WindowListener。不要让 media presentation import `WindowListener` 或 `window_manager`。

- [ ] **Step 5: Implement actual/desired serialization**

controller 字段至少包括 `_initialFullscreen`、`_actualFullscreen`、`_desiredFullscreen`、`_commandInFlight`、`_disposed`、`Future<void> _tail`、递增 request generation，以及只创建一次的 `_initialization` Future。

`initializeSession()` 幂等读取初始状态并注册 listener；它捕获 gateway 异常并记录初始化失败，不能让页面的 `unawaited` 调用产生未处理 Future 错误。`toggle()`、`exitIfFullscreen()`、`restoreAndDispose()` 都先 await 同一个 `_initialization`；初始化失败时分别返回 `consumed: true, succeeded: false` 或 `false`，因此页面无需依赖“初始化恰好先于首个 F/Escape 完成”的时序。

`WindowsVideoFullscreenController` 构造器注入 `VideoWindowErrorReporter errorReporter = reportVideoWindowError`。默认 reporter 只 `debugPrint('[WindowsVideoFullscreen] $operation 失败 (${error.runtimeType})')`，不得输出 `error.toString()`、媒体 URI、headers 或 stack trace；测试 reporter 可记录结构化参数。初始化、toggle、exit、restore 的每个 catch 都报告固定 operation，页面只看到 `无法切换全屏`。关闭恢复失败仍继续 route pop。

所有命令先同步更新 desired，再把 `_reconcile(generation)` 串到 `_tail.then(...)`。`_reconcile` 只在 actual != desired 时调用一次 gateway；成功后以 gateway event 或完成后的 `isFullScreen()` 校准 actual。失败结果规则：只有失败 generation 仍是最新请求时才把 desired 回退 actual；已有更新请求则保留更新 desired 继续 reconcile。

外部事件处理：

```dart
void _onFullscreenChanged(bool value) {
  _actualFullscreen = value;
  if (!_commandInFlight) _desiredFullscreen = value;
}
```

`restoreAndDispose()` 先 desired=initial，await queue，移除 listener，幂等返回是否恢复成功。

- [ ] **Step 6: Add the Windows-only bootstrap seam**

`bootstrap` 新增两个仅供测试注入的可选参数；显式 `hostPlatform` 让非 Windows 分支不依赖修改全局平台状态：

```dart
typedef WindowsWindowInitializer = Future<void> Function();

Future<void> bootstrap({
  SharedPreferences? sharedPreferences,
  AppDatabase? database,
  NetworkLogger? networkLogger,
  WindowsWindowInitializer? windowsWindowInitializer,
  TargetPlatform? hostPlatform,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final effectivePlatform = hostPlatform ?? defaultTargetPlatform;
  if (effectivePlatform == TargetPlatform.windows) {
    await (windowsWindowInitializer ?? initializeWindowsVideoWindowRuntime)();
  }
  // 之后保持 SharedPreferences → database → logger → onAppLaunch → runApp。
}
```

`initializeWindowsVideoWindowRuntime()` 只调用 `windowManager.ensureInitialized()`。bootstrap integration helper 显式传 `hostPlatform: TargetPlatform.windows` 与 `windowsWindowInitializer: () async {}`；新增 Windows 计数测试证明调用一次且真实插件不被触发，并以 `TargetPlatform.android` 证明 initializer 不调用。

- [ ] **Step 7: Update canonical startup documentation**

在 `AGENTS.md` 将五个可选参数及顺序写为：binding → Windows window runtime（仅 Windows）→ SharedPreferences → DB → logger → `onAppLaunch` → runApp；说明测试可注入 host platform 与 no-op window initializer，生产全部传 null。

- [ ] **Step 8: Run tests, architecture gate, format and commit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/platform/windows_video_fullscreen_controller_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task4-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task4-green.log
dart run tool/check_import_boundaries.dart
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
git add pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake lib/app/platform/windows_video_fullscreen_controller.dart lib/bootstrap.dart AGENTS.md test/app/platform/windows_video_fullscreen_controller_test.dart test/integration/bootstrap_integration_test.dart
git diff --cached --check
git commit -m "feat(media): 接入 Windows 原生视频全屏"
git status --short
```

Expected: tests/gate exit `0`; commit includes dependency + adapter + bootstrap/doc contract only；页面尚未调用全屏 adapter。

---

### Task 5: Compose platform bindings and wire Desktop keyboard/fullscreen into the page

**Files:**
- Create: `lib/app/platform/android_video_system_ui_controller.dart`
- Create: `lib/app/composition/video_player_platform_bindings_factory.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/features/media/presentation/pages/media_route_pages.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `lib/features/media/presentation/pages/mobile_video_interaction_controller.dart`
- Create: `test/app/composition/video_player_platform_bindings_factory_test.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/features/media/presentation/pages/media_route_pages_test.dart`
- Create: `test/features/media/presentation/pages/video_player_desktop_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_page_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_accessibility_test.dart`

**Interfaces:**
- Consumes: Tasks 1-4 controllers, bindings, Windows adapter and fake ports.
- Produces: production TargetPlatform selection, Android SystemChrome session, Desktop initial focus/key/fullscreen/Escape behavior, route-level bindings injection.

- [ ] **Step 1: Write platform composition tests red**

```dart
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
```

非 Windows/Android 平台必须抛出带固定安全消息的 `UnsupportedError`，不能默认为 Mobile。

- [ ] **Step 2: Write Desktop page red tests**

建立 `_pumpDesktopVideo` helper，显式传 `DesktopVideoPlayerBindings(fullscreen: fake)`。添加：

```dart
testWidgets('Desktop 初始化成功后播放表面自动获得主焦点', (tester) async {
  final harness = await pumpDesktopVideo(tester);
  expect(harness.surfaceFocusNode.hasPrimaryFocus, isTrue);
});

testWidgets('Desktop 左右键按五秒且右键短按在 KeyUp 执行', (tester) async {
  final harness = await pumpDesktopVideo(tester, position: const Duration(seconds: 30));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
  expect(harness.fake.seekToCalls, isEmpty);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
  expect(harness.fake.seekToCalls.last, const Duration(seconds: 35));

  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
  expect(harness.fake.seekToCalls.last, const Duration(seconds: 30));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
});

testWidgets('Desktop 全屏 Escape 只退出全屏再次 Escape 才关闭页面',
    (tester) async {
  final harness = await pumpPushedDesktopVideo(tester, fullscreen: true);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  expect(harness.fullscreen.calls, contains('exitIfFullscreen'));
  expect(find.text('打开播放器'), findsNothing);

  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.pump();
  expect(find.text('打开播放器'), findsOneWidget);
});
```

再测：M/上下、F、failure feedback、表面失焦取消右键、控制焦点不抢方向键、Popup/Dialog Escape 优先、close await restore。

- [ ] **Step 3: Run composition/Desktop tests red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/composition/video_player_platform_bindings_factory_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task5-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task5-red.log
```

Expected: non-zero，因为 app composition/page 尚未接入 bindings。

- [ ] **Step 4: Implement Android SystemChrome adapter**

```dart
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
```

页面不再直接调用 SystemChrome。restore 幂等，dispose fallback 用 `unawaited`。

- [ ] **Step 5: Implement the sole platform bindings factory**

`createVideoPlayerPlatformBindingsFactory` 位于 app composition，参数含显式 `TargetPlatform` 方便测试；生产 wrapper 读取 `defaultTargetPlatform`：

```dart
VideoPlayerPlatformBindingsFactory createAppVideoPlayerBindingsFactory() =>
    createVideoPlayerPlatformBindingsFactory(
      platform: defaultTargetPlatform,
      windowsFullscreenFactory: () => WindowsVideoFullscreenController(
        gateway: WindowManagerVideoWindowGateway(),
      ),
      mobileSystemUiFactory: AndroidVideoSystemUiController.new,
    );
```

media presentation 不 import `flutter/foundation.dart` platform globals。

- [ ] **Step 6: Thread the factory through router and route page**

`createAppRouter` 增加必需或具 app-level default 的 `videoPlayerBindingsFactory` 参数；`appRouterProvider` 创建一次 production factory 并传入。`MediaVideoRoutePage` 增加 required `bindingsFactory`，资源解析成功后传给 `VideoPlayerPage`；恢复页不创建 bindings。

所有 direct route/page tests 显式传 fake Mobile/Desktop factory，禁止在测试依赖 host Windows 默认平台。

- [ ] **Step 7: Rebuild `VideoPlayerPage` around sealed bindings**

State `initState` 调 factory 一次：

```dart
late final VideoPlayerPlatformBindings _bindings;
MobileVideoInteractionController? _mobile;
DesktopVideoInteractionController? _desktop;

@override
void initState() {
  super.initState();
  _bindings = widget.platformBindingsFactory();
  switch (_bindings) {
    case MobileVideoPlayerBindings(:final systemUi):
      _mobile = MobileVideoInteractionController(playback: _playback);
      unawaited(systemUi.enter());
    case DesktopVideoPlayerBindings(:final fullscreen):
      _desktop = DesktopVideoInteractionController(
        playback: _playback,
        fullscreen: fullscreen,
        onRequestClose: _requestClose,
        onInteractionChanged: _handleStateChanged,
      );
      unawaited(fullscreen.initializeSession());
  }
}
```

实际实现必须先构造 `_playback` 再构造 interaction。初始化成功回调在 Desktop 下一帧 requestFocus；Mobile 不 autofocus。

交互层 exhaustive switch：Mobile 构建现有 RawGestureDetector；Desktop 只构建 tap/double-tap 基础层（鼠标 activity/scroll Task 6）。Mobile key handler继续 ±15 秒；Desktop surface/page handlers 使用 Task 3。

- [ ] **Step 8: Implement one asynchronous close path**

```dart
Future<void> _requestClose() async {
  if (_closing) return;
  _closing = true;
  final bindings = _bindings;
  if (bindings is DesktopVideoPlayerBindings) {
    await bindings.fullscreen.restoreAndDispose();
  } else if (bindings is MobileVideoPlayerBindings) {
    await bindings.systemUi.restore();
  }
  if (!mounted) return;
  setState(() => _allowPop = true);
  await WidgetsBinding.instance.endOfFrame;
  if (mounted) Navigator.of(context).pop();
}
```

顶部关闭、windowed Escape 和 route back 调同一路径。等待 `endOfFrame` 只用于让 `PopScope.canPop` 的放行状态进入树，不是通用异步 flush。`dispose` 仍触发幂等 unawaited restore fallback；不得 await in dispose。PopupRoute 先消费 Escape；页面 root handler 只在事件冒泡到视频页时处理。

用 `PopScope(canPop: false, onPopInvokedWithResult: ...)` 拦截 Android 系统返回、Windows 系统返回与 GoRouter pop，并转发 `_requestClose()`；`_requestClose()` 内部恢复完成后执行真正 pop 时用 `_allowPop` 短暂放行，避免递归。顶部关闭回调用 `() => unawaited(_requestClose())`。页面实现 `WidgetsBindingObserver`：`AppLifecycleState.inactive` 或 `paused` 都交给共享核心暂停；Desktop 同时调用 `desktop.onWindowBlur()`，保证 Alt+Tab/窗口失焦时取消右键分类、释放临时倍速并恢复可见光标，但不退出原生全屏。

- [ ] **Step 9: Preserve Android and update route/router tests**

Android tests 显式 Mobile bindings，继续断言：单击 controls、double ±15、long press 3x、drag commit/cancel、`systemGestureInsets` 边缘让位、无 autofocus、外接键盘 KeyDown 立即 ±15 且 repeat 忽略、SystemUI fake enter/restore 一次。router route path/name/query 完全不变；测试只新增 factory dependency，不修改 URL 断言。

- [ ] **Step 10: Run the vertical green suite and architecture audit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/composition/video_player_platform_bindings_factory_test.dart test/app/router/app_router_test.dart test/features/media/presentation/pages/media_route_pages_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task5-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task5-green.log
dart run tool/check_import_boundaries.dart
rg -n "defaultTargetPlatform|TargetPlatform|Platform\.isWindows|window_manager|SystemChrome" lib/features/media
```

Expected: tests/gate `0`; media 命中只允许 Flutter input/detail types和 presentation-owned ports，不允许平台选择、window plugin、SystemChrome concrete call。

- [ ] **Step 11: Format and commit the platform vertical slice**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
$StagePaths = @(
  'lib/app/platform/android_video_system_ui_controller.dart',
  'lib/app/composition/video_player_platform_bindings_factory.dart',
  'lib/app/router/app_router.dart',
  'lib/features/media/presentation/pages/media_route_pages.dart',
  'lib/features/media/presentation/pages/video_player_page.dart',
  'lib/features/media/presentation/pages/mobile_video_interaction_controller.dart',
  'test/app/composition/video_player_platform_bindings_factory_test.dart',
  'test/app/router/app_router_test.dart',
  'test/features/media/presentation/pages/media_route_pages_test.dart',
  'test/features/media/presentation/pages/video_player_desktop_test.dart',
  'test/features/media/presentation/pages/video_player_page_test.dart',
  'test/features/media/presentation/pages/video_player_accessibility_test.dart',
  'test/features/media/helpers/fake_video_player_platform_bindings.dart'
)
git add -- $StagePaths
git diff --cached --check
git commit -m "feat(media): 按平台组合视频播放器输入"
git status --short
```

Expected: Windows 已启用键盘/全屏，Android 行为等价；Desktop 鼠标活动与滚轮仍留给 Task 6。

---

### Task 6: Add Desktop mouse activity, cursor policy and wheel volume

**Files:**
- Modify: `lib/features/media/presentation/pages/desktop_video_interaction_controller.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `lib/features/media/presentation/widgets/video_player_controls.dart`
- Modify: `test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_desktop_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_accessibility_test.dart`

**Interfaces:**
- Consumes: Task 1 controls timer/volume commands and Task 5 Desktop page surface.
- Produces: pointer activity policy, three-second idle cursor/controls hiding, vertical wheel 5% leading-edge throttle, single-click play/pause and double-click fullscreen.

- [ ] **Step 1: Add failing controller tests for independent visibility inputs**

给 Desktop controller 增加公开只读 `bool get isCursorVisible`，并用注入的 fake timers 验证以下中文用例：

```dart
test('播放中鼠标活动显示控件与光标并在三秒静止后同时隐藏', () {
  final harness = createDesktopHarness(isPlaying: true);

  harness.controller.onPointerActivity();
  expect(harness.playback.state.controlsVisible, isTrue);
  expect(harness.controller.isCursorVisible, isTrue);

  harness.timers.elapse(const Duration(seconds: 3));
  expect(harness.playback.state.controlsVisible, isFalse);
  expect(harness.controller.isCursorVisible, isFalse);
});

test('暂停结束控件悬停或控件焦点均阻止自动隐藏', () {
  final harness = createDesktopHarness(isPlaying: true);
  harness.controller.onControlsPointerEnter();
  harness.timers.elapse(const Duration(seconds: 3));
  expect(harness.playback.state.controlsVisible, isTrue);

  harness.controller.onControlsPointerExit();
  harness.controller.onControlsFocusChanged(true);
  harness.timers.elapse(const Duration(seconds: 3));
  expect(harness.playback.state.controlsVisible, isTrue);
});
```

再覆盖：悬停退出但焦点仍在时不释放；暂停/ended 状态不启动 idle timer；播放恢复后从最后一次 activity 重新计时；window blur、retry、dispose 取消 timer 并把 controls/cursor 恢复可见。不要检查 Widget 私有 Key 或 `MouseRegion.cursor` 属性，controller 的公开投影是这一规则的最低稳定契约。

- [ ] **Step 2: Add failing scroll classifier tests**

入口固定为 `void handlePointerSignal(PointerSignalEvent event)`。测试：

- `PointerScrollEvent(scrollDelta: Offset(0, -1))` 调高 `0.05`；正 y 调低 `0.05`；
- `abs(dx) >= abs(dy)` 的纯水平/横向主导事件完全忽略；
- 第一个垂直事件立即生效，50ms 内后续事件忽略；fake timer 到期后的下一事件立即生效；
- clamp 到 0/1，并显示实际百分比的 `VideoVolumeFeedback`；
- 非 scroll signal 不抛异常、不改状态。

- [ ] **Step 3: Add failing Desktop page pointer tests**

```dart
testWidgets('Desktop 画面单击切换播放且双击只切换全屏', (tester) async {
  final harness = await pumpDesktopVideo(tester);

  await tester.tap(harness.videoSurface);
  expect(harness.fake.pauseCallCount, 1);

  await tester.tap(harness.videoSurface);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(harness.videoSurface);
  await tester.pump();
  expect(harness.fullscreen.toggleCallCount, 1);
  expect(harness.fake.seekToCalls, isEmpty);
});
```

实际 Widget 测试使用 Flutter test binding 支持的双击事件序列，不依赖生产固定延迟；若 `tester.tap` 会提前提交 single tap，则改用 `TestGesture` 发送两组 pointer down/up 并断言 recognizer 的标准仲裁结果。再用 `tester.sendEventToBinding(PointerHoverEvent(...))` 和 `PointerScrollEvent` 验证页面确实把事件转发给 Desktop controller。

- [ ] **Step 4: Run Task 6 red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task6-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task6-red.log
```

Expected: non-zero，失败来自尚未实现的 mouse/cursor/wheel contract。

- [ ] **Step 5: Implement one Desktop visibility state machine**

共享核心继续独占控制栏三秒 hide timer；Desktop controller 只拥有光标三秒 timer，并在同一 activity 时点调用 `playback.showControls()`，使两者同步但不争夺同一个状态。Desktop 私有字段至少包括 `_pointerInsideControls`、`_controlsHaveFocus`、`_holdsPlaybackControls`、`_isCursorVisible`、`_cursorIdleTimer`。集中实现：

```dart
bool get _mustStayVisible =>
    !_playback.state.isPlaying ||
    _playback.state.hasEnded ||
    _pointerInsideControls ||
    _controlsHaveFocus;

void _scheduleCursorHide() {
  _cursorIdleTimer?.cancel();
  if (_mustStayVisible) {
    _isCursorVisible = true;
    return;
  }
  _cursorIdleTimer = _timerFactory(const Duration(seconds: 3), () {
    if (_mustStayVisible) return;
    _isCursorVisible = false;
    _onInteractionChanged();
  });
}
```

`onPointerActivity()` 同时设置 cursor visible、调用 `playback.showControls()` 并重启 cursor timer。页面每次共享播放 state 变化后调用 `desktop.onPlaybackStateChanged()`；controller 只在状态从 playing/ended 等影响 policy 的值变化时重排 timer，避免每个 position tick 都重启三秒计时。controller 先合并 hover/focus 多来源，aggregate 从 false→true 时调用一次 `holdControlsVisible()`，true→false 时调用一次 `releaseControlsHold()` 并同步启动 cursor timer；不得让一个来源退出错误释放另一个来源的 hold。

- [ ] **Step 6: Implement pointer and controls boundaries**

Desktop page 使用 `MouseRegion(onHover/onEnter: ...)` 包住播放 surface，cursor 根据 `desktop.isCursorVisible` 选择 `SystemMouseCursors.basic` 或 `SystemMouseCursors.none`。使用 `Listener(onPointerSignal: desktop.handlePointerSignal)`；不要把 scroll 接到 Mobile subtree。

现有 controls 根部增加可选的 `onPointerEnter`、`onPointerExit`、`onFocusChanged` 回调，并用一个 `Focus`/`MouseRegion` 汇总所有子控件。默认 null 时行为与 Android 等价。任何 popup/menu 打开前调用 controls focus/hold 路径，关闭后依据真实 focus/hover 重新计算，不用固定延迟猜测菜单已关闭。

- [ ] **Step 7: Implement click/double-click and wheel semantics**

Desktop surface 使用标准 `GestureDetector(onTap: playback.togglePlayPause, onDoubleTap: ...)`；double tap 调 fullscreen，失败只显示 `VideoOperationFailureFeedback('无法切换全屏')`。不得调用 Seek，也不得复用 Mobile double-tap position。

滚轮逻辑先判断 vertical-dominant，再判断 `_wheelThrottled`；接受后立即 `adjustVolume(scrollDelta.dy < 0 ? 0.05 : -0.05)` 并启动 50ms timer。该 timer 与三秒 idle timer 分开持有、分别取消；scroll 也算 pointer activity。

- [ ] **Step 8: Run green, format and commit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task6-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/desktop-video-task6-green.log
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
dart format $DartFiles
dart format --output=none --set-exit-if-changed $DartFiles
git add lib/features/media/presentation/pages/desktop_video_interaction_controller.dart lib/features/media/presentation/pages/video_player_page.dart lib/features/media/presentation/widgets/video_player_controls.dart test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart
git diff --cached --check
git commit -m "feat(media): 完成 Windows 视频鼠标操控"
git status --short
```

Expected: Desktop 鼠标 contract 完整；Android tests 未发生行为变化；只有计划文件未提交。

---

### Task 7: Consolidate platform regression and accessibility contracts

**Files:**
- Modify: `test/features/media/presentation/pages/video_player_page_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_desktop_test.dart`
- Modify: `test/features/media/presentation/pages/video_player_accessibility_test.dart`
- Modify: `test/features/media/presentation/pages/media_route_pages_test.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/integration/bootstrap_integration_test.dart`
- Modify: `lib/features/media/presentation/pages/video_player_page.dart` only if a regression test exposes a real composition defect
- Modify: `lib/features/media/presentation/widgets/video_player_controls.dart` only if a regression test exposes a real semantics defect

**Interfaces:**
- Consumes: finished Mobile/Desktop vertical slices.
- Produces: explicit cross-platform behavior matrix with no duplicate external contracts and platform-specific accessible help.

- [ ] **Step 1: Audit existing tests before adding cases**

```powershell
rg -n "双击|长按|横向|方向键|Escape|全屏|音量|静音|Semantics|hint|focus" test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart
```

对每个拟新增断言先指出现有测试是否已覆盖同一 external contract、层级和预期失败原因。迁移 controller 级断言后，从 Widget 测试删除只验证内部调用次数的重复项，但保留真实 composition、focus、gesture arena、route pop 和 Semantics 契约。

- [ ] **Step 2: Add the missing platform-negative tests red**

新增/补强中文用例：

- Desktop 双击不 Seek、画面长按不 3x、横拖不 preview/commit Seek；触摸 pointer 也仍走 Desktop policy；
- Desktop Left KeyRepeat 无副作用，Right 进入 3x 后 KeyUp 不 Seek，Right 在 paused/ended 到阈值时 KeyUp 也不 Seek；
- Desktop window blur/retry/dispose 清理 3x lease、分类 timer、wheel timer 和 cursor timer；
- Desktop Up/Down repeat 每次 5%，M 的显式 mute/manual-zero 恢复规则；
- Mobile 仍是 ±15 秒、长按 3x、横拖 Seek、单击 controls，且不被 Desktop M/F/音量快捷键改变；
- route factory 每次进入页面产生独立 session，恢复页/无效资源不创建 bindings；
- bootstrap 在 `hostPlatform: TargetPlatform.android` 时不调用 initializer；禁止篡改全局 `Platform` 或 `debugDefaultTargetPlatformOverride`。

只先添加当前实现确实缺失的契约；若全部已 green，则记录审计结果，不制造假 red。

- [ ] **Step 3: Add platform-specific accessibility tests red**

将帮助文本/语义从通用固定文案改为 bindings 决定：

- Android 描述单击控制栏、双击 ±15 秒、长按 3 倍速与横拖 Seek；
- Windows 描述单击播放、双击全屏、左右 5 秒、右键长按 3 倍速、上下 5% 音量、M、F、Escape；
- 动态 center feedback 使用 live region，并分别验证 `快进 5 秒`、`音量 55%`、`静音`、`3 倍速`、`无法切换全屏`；
- Desktop autofocus 后键盘等价操作可达；controls 获得焦点时箭头属于控件自身，不被 surface 全局抢走；
- 普通 Material 控件不重复包装同义 Semantics。

- [ ] **Step 4: Run the regression matrix red/diagnostic**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart test/features/media/presentation/pages/media_route_pages_test.dart test/app/router/app_router_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task7-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/desktop-video-task7-red.log
```

Expected: 新增缺失契约时 non-zero 且失败原因精确；若审计证明无需新增 red case，日志允许 `EXIT=0`，但任务记录必须列出哪些现有测试承担每项契约。

- [ ] **Step 5: Fix only exposed composition/semantics gaps**

修复限制在本任务 Files 列表。不要借测试整理重排控制栏布局、添加快捷键设置或改变 Android gesture arena。异步断言等待 fullscreen fake Future、Focus state、controller state 或受控 timer；不得新增 `Future.delayed`/通用 `pumpAndSettle()`。

- [ ] **Step 6: Run all media tests and static ownership audit**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media --reporter compact 2>&1 | Out-File -Encoding utf8 logs/desktop-video-task7-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/desktop-video-task7-green.log
rg -n "setPlaybackSpeed|setVolume|seekTo\(|\.play\(\)|\.pause\(\)" lib/features/media/presentation
rg -n "CenterHintType|15 秒|15s|SystemChrome|window_manager|Platform\.is|defaultTargetPlatform" lib/features/media
```

Expected: `EXIT=0`；底层播放写操作只命中 `video_playback_controller.dart`；`15 秒` 仅存在 Android 文案/契约，presentation 不命中 concrete platform/plugin 调用。

- [ ] **Step 7: Format and commit regression protection**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
if ($DartFiles) {
  dart format $DartFiles
  dart format --output=none --set-exit-if-changed $DartFiles
}
git add -- test/features/media/presentation/pages/video_player_page_test.dart test/features/media/presentation/pages/video_player_desktop_test.dart test/features/media/presentation/pages/video_player_accessibility_test.dart test/features/media/presentation/pages/media_route_pages_test.dart test/app/router/app_router_test.dart test/integration/bootstrap_integration_test.dart lib/features/media/presentation/pages/video_player_page.dart lib/features/media/presentation/widgets/video_player_controls.dart
git diff --cached --check
git commit -m "test(media): 补齐跨平台视频操控回归"
git status --short
```

在 commit 前用 `git diff --cached --name-only` 确认没有把本计划或无关用户改动纳入。若 Task 7 审计完全没有文件变化，则跳过空提交并在执行记录中说明。

---

### Task 8: Update product documentation and run final gates

**Files:**
- Modify: `docs/视频局域网广播-prd.md`
- Modify: `README.md`
- Verify only: all implementation/test files from Tasks 1-7

**Interfaces:**
- Consumes: approved design and implemented behavior.
- Produces: user-facing platform contract, final automated evidence, explicit manual-smoke status and scope audit.

- [ ] **Step 1: Update documentation without claiming unrun verification**

在 PRD 的播放器章节把“通用移动手势”拆成 Android/Windows 两表。Windows 表必须逐项写明 5 秒、400ms、纯 3x、5% 音量、M、F/Escape、单/双击、3 秒 idle、50ms wheel throttle；Android 表明确保留既有 ±15 秒/长按/横拖。README 只写简短入口与核心快捷键并链接 PRD，避免复制完整状态机。

文档同时写明：Windows 触摸屏仍采用 Desktop policy；没有常驻倍速快捷键；真正全屏会在离开播放器时恢复进入前窗口状态。不得写“已在 Windows/Android 实机验证”，除非 Step 8 确实完成。

- [ ] **Step 2: Review and commit documentation before final builds**

```powershell
git diff --check
git diff -- docs/视频局域网广播-prd.md README.md
git add docs/视频局域网广播-prd.md README.md
git diff --cached --check
git commit -m "docs(media): 记录分平台视频操控"
git status --short
git log -1 --oneline
Select-String -Pattern '^version:' pubspec.yaml
```

Expected: post-commit hook 已把最终版本并入该 commit；此后所有 build 都基于最终 HEAD。计划文件仍未提交。

- [ ] **Step 3: Verify formatting for every changed Dart file since baseline**

```powershell
$ChangedDart = git diff 0a2c33cf9e24bb27625cbcbbe409b3a57c74b41a..HEAD --name-only --diff-filter=ACMR -- '*.dart'
if ($ChangedDart) {
  dart format --output=none --set-exit-if-changed $ChangedDart
}
git diff --check
```

Expected: exit `0` 且不产生新 diff。若格式检查改动文件，格式化、按归属补交一个窄提交，然后重新从 Step 2 的最终 HEAD 检查版本并重跑后续全部门禁。

- [ ] **Step 4: Run architecture and static analysis serially**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/desktop-video-architecture.log
$BoundaryExit = $LASTEXITCODE
Write-Host "BOUNDARY_EXIT=$BoundaryExit"
Get-Content -Tail 120 logs/desktop-video-architecture.log
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/desktop-video-analyze.log
$AnalyzeExit = $LASTEXITCODE
Write-Host "ANALYZE_EXIT=$AnalyzeExit"
Get-Content -Tail 150 logs/desktop-video-analyze.log
```

Expected: both `0`。若 analyze 在依赖解析后停滞，确认无残留进程后改用 `flutter analyze --no-pub` 写回同一日志；不要并行跑重型 gate。

- [ ] **Step 5: Run the full test suite with mandatory redirection**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/fltest.log
```

Expected: `EXIT=0`。启动前卡住时运行 `./scripts/kill-stale-test-processes.ps1` 后仅重试一次；测试失败必须从 `logs/fltest.log` 定位并修复，不得把环境失败算通过。

- [ ] **Step 6: Build final Windows Debug and Release artifacts**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter build windows --debug 2>&1 | Out-File -Encoding utf8 logs/desktop-video-build-windows-debug.log
$DebugExit = $LASTEXITCODE
Write-Host "DEBUG_EXIT=$DebugExit"
Get-Content -Tail 120 logs/desktop-video-build-windows-debug.log
flutter build windows --release 2>&1 | Out-File -Encoding utf8 logs/build-windows.log
$ReleaseExit = $LASTEXITCODE
Write-Host "RELEASE_EXIT=$ReleaseExit"
Get-Content -Tail 150 logs/build-windows.log
```

Expected: both `0`。确认最终二进制来自 Step 2 后的 HEAD/version。若生成文件发生变化，只允许 Flutter 正常 plugin registration 产物且必须先判断是否应提交。

- [ ] **Step 7: Compile-check Android without changing its product contract**

```powershell
flutter build apk --debug 2>&1 | Out-File -Encoding utf8 logs/desktop-video-build-android-debug.log
$AndroidExit = $LASTEXITCODE
Write-Host "ANDROID_EXIT=$AndroidExit"
Get-Content -Tail 150 logs/desktop-video-build-android-debug.log
```

Expected: `0`。SDK/keystore/网络环境缺失要精确记录为 environment blocked，不能表述为代码失败或成功；不为通过该 gate 改 Android 签名策略。

- [ ] **Step 8: Perform the manual smoke matrix or mark every item pending**

Windows 真机窗口：

- 本地/远端视频各打开一次；single click、double click、F、Escape/顶部关闭；
- Left 5 秒、Right tap 5 秒、Right hold 400ms 后纯 3x/释放恢复；重复键不误触；
- Up/Down 5%、M 显式 mute/manual zero 恢复；wheel 方向/5%/50ms；
- playing idle 3 秒隐藏 controls/cursor，paused/ended/hover/focus 常驻；alt-tab/失焦恢复；
- 从普通窗口、最大化窗口、已全屏三种初始状态进入/退出页面，关闭后恢复初始状态/窗口大小位置；快速连续 F/F/Escape 和全屏失败路径不关闭页面。

Android 设备：single controls、double ±15、long press 3x、horizontal drag/cancel、系统返回/SystemUI 恢复、外接键盘 ±15（有设备时）。未实际执行的每一项写 `pending`，不要用 Widget 测试代替。

- [ ] **Step 9: Final scope and ownership audit**

```powershell
git status --short
git diff 0a2c33cf9e24bb27625cbcbbe409b3a57c74b41a..HEAD --stat
git diff 0a2c33cf9e24bb27625cbcbbe409b3a57c74b41a..HEAD --name-only
git log --oneline 0a2c33cf9e24bb27625cbcbbe409b3a57c74b41a..HEAD
rg -n "setPlaybackSpeed|setVolume|seekTo\(|\.play\(\)|\.pause\(\)" lib/features/media/presentation
rg -n "window_manager|SystemChrome|defaultTargetPlatform|Platform\.is" lib/features/media
```

Acceptance:

- functional diff 只涉及计划列出的 media/app/bootstrap/plugin/docs/tests；无 Sync/MediaLibrary/domain/data 改动；
- playback writes 仅由 `VideoPlaybackController` owner 发出；平台具体实现只在 app adapter/composition；
- Windows/Desktop 与 Android/Mobile negative contracts 均有测试；全量、analyze、boundary、Windows build 有明确 exit code；
- 工作区只允许留下未获授权的本计划文件和可再生成的 ignored logs/build 产物；任何其他未提交文件都必须归属清楚；
- 不 push、不建 PR。向用户报告最终 HEAD/version、每个 gate、Windows/Android manual smoke 的 passed/failed/pending，且严格区分自动验证与设备验证。
