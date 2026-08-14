import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 用于测试的 Fake VideoPlayerController。
///
/// 不依赖平台原生播放器，所有方法通过覆写实现。
/// 提供可追踪的 [seekToCalls] 和 [setPlaybackSpeedCalls] 列表，
/// 以及可设置的 [fakePosition]、[fakeDuration] 等状态字段。
class FakeVideoPlayerController extends VideoPlayerController {
  // ── 追踪列表 ──
  final List<Duration> seekToCalls = [];
  final List<double> setPlaybackSpeedCalls = [];
  final List<double> setVolumeCalls = [];
  int playCallCount = 0;
  int pauseCallCount = 0;
  int disposeCount = 0;

  // ── 可设置的状态（测试驱动用） ──
  Duration fakePosition = Duration.zero;
  Duration fakeDuration = const Duration(minutes: 5);
  bool fakeIsPlaying = true;
  bool fakeIsCompleted = false;
  bool fakeIsInitialized = true;
  double fakePlaybackSpeed = 1.0;
  double fakeVolume = 1.0;
  double fakeBufferedPercent = 0.5;

  // ── 初始化控制（确定性失败与时序） ──
  /// 设置后 [initialize] 递增计数后确定性抛出该错误。
  Object? initializeError;
  int initializeCallCount = 0;
  final List<({int expected, Completer<void> completer})> _initializeWaiters =
      [];

  /// 等待第 [expected] 次 [initialize] 完成（含失败）。已满足时立即完成，
  /// 未满足时注册带期望次数的 waiter，由 [initialize] 按计数逐一放行：
  /// 各等待方携带自己的 expected，互不提前唤醒，避免复用首次已完成的
  /// Completer。
  Future<void> waitForInitializeCount(int expected) {
    if (initializeCallCount >= expected) return Future<void>.value();
    final completer = Completer<void>();
    _initializeWaiters.add((expected: expected, completer: completer));
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        '等待第 $expected 次视频初始化',
        const Duration(seconds: 5),
      ),
    );
  }

  FakeVideoPlayerController({this.initializeError})
    : super.networkUrl(Uri.parse('http://localhost/test.mp4'));

  // ── 覆写核心方法 ──

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    // 只放行期望次数已达成的 waiter，保证「第 N 次」与调用计数严格对应；
    // 放行即从列表移除，已完成项不再参与后续遍历。
    _initializeWaiters.removeWhere((waiter) {
      if (waiter.expected <= initializeCallCount) {
        if (!waiter.completer.isCompleted) waiter.completer.complete();
        return true;
      }
      return false;
    });
    if (initializeError != null) {
      fakeIsInitialized = false;
      _updateValue();
      throw initializeError!;
    }
    fakeIsInitialized = true;
    _updateValue();
  }

  @override
  Future<void> play() async {
    playCallCount++;
    fakeIsPlaying = true;
    _updateValue();
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    fakeIsPlaying = false;
    _updateValue();
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekToCalls.add(position);
    fakePosition = position;
    // 与真实 VideoPlayerController 一致：seek 到结尾时标记为已完成
    fakeIsCompleted = position >= fakeDuration;
    _updateValue();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    setPlaybackSpeedCalls.add(speed);
    fakePlaybackSpeed = speed;
    _updateValue();
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls.add(volume);
    fakeVolume = volume;
    _updateValue();
  }

  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    disposeCount++;
    // 不调用平台 dispose（测试中无平台通道）
  }

  /// 主动触发一次 value 变化通知。
  ///
  /// 测试直接修改 [fakePosition] / [fakeIsPlaying] 等字段后调用，让
  /// 控制器监听器按新值投影状态；与 `seekTo`/`play`/`pause` 等命令
  /// 触发通知的方式等价，但不产生命令追踪记录。
  void emitValueChanged() => _updateValue();

  /// 通知监听器状态已更新。
  void _updateValue() {
    value = VideoPlayerValue(
      duration: fakeDuration,
      size: const Size(1920, 1080),
      position: fakePosition,
      isPlaying: fakeIsPlaying,
      isCompleted: fakeIsCompleted,
      isBuffering: false,
      isInitialized: fakeIsInitialized,
      playbackSpeed: fakePlaybackSpeed,
      volume: fakeVolume,
      buffered: fakeBufferedPercent > 0
          ? [
              DurationRange(
                Duration.zero,
                Duration(
                  milliseconds:
                      (fakeDuration.inMilliseconds * fakeBufferedPercent)
                          .round(),
                ),
              ),
            ]
          : const [],
    );
  }
}
