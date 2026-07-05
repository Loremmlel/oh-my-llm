import 'dart:async';

import 'package:video_player/video_player.dart';

import '../widgets/video_player_controls.dart';

/// 视频播放器 UI 状态。
class VideoPlayerUiState {
  // ── 播放器状态 ──
  VideoPlayerController? controller;
  bool isInitialized = false;
  bool hasError = false;
  String? errorMessage;

  // ── 控制栏状态 ──
  bool controlsVisible = true;
  double currentSpeed = 1.0;
  double currentVolume = 1.0;
  Timer? hideTimer;
  bool isDragging = false;
  double dragPositionMs = 0.0;
  double bufferedPercent = 0.0;
  bool hasEnded = false;

  // ── 手势状态 ──
  double? lastTapPositionDx;
  bool isLongPressing = false;
  double preLongPressSpeed = 1.0;
  bool isHorizontalDragging = false;
  Duration seekPreviewPosition = Duration.zero;
  Duration dragStartPosition = Duration.zero;
  double dragStartDx = 0;
  CenterHintType centerHint = CenterHintType.none;
  Timer? hintTimer;
  bool? controlsVisibleBeforeGesture;
  double cachedScreenWidth = 0;

  // ── 播放同步状态 ──
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
}
