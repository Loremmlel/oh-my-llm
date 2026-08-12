import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

// ── 状态定义 ────────────────────────────────────────────

sealed class ShufflePlaybackState extends Equatable {
  const ShufflePlaybackState();
}

class ShufflePlaybackIdle extends ShufflePlaybackState {
  const ShufflePlaybackIdle();

  @override
  List<Object?> get props => const [];
}

class ShufflePlaybackLoading extends ShufflePlaybackState {
  const ShufflePlaybackLoading();

  @override
  List<Object?> get props => const [];
}

class ShufflePlaybackActive extends ShufflePlaybackState {
  ShufflePlaybackActive({
    required List<VideoItem> playlist,
    required this.currentIndex,
    required this.directoryPath,
  }) : playlist = List.unmodifiable(playlist);

  final List<VideoItem> playlist;
  final int currentIndex;
  final String directoryPath;

  @override
  List<Object?> get props => [playlist, currentIndex, directoryPath];

  bool get isFirst => currentIndex == 0;
  bool get isLast => currentIndex >= playlist.length - 1;
  VideoItem get currentVideo => playlist[currentIndex];
  int get totalCount => playlist.length;
  int get displayNumber => currentIndex + 1; // 1-based for display
}

// ── Provider ────────────────────────────────────────────

final shufflePlaybackControllerProvider =
    NotifierProvider<ShufflePlaybackController, ShufflePlaybackState>(
      ShufflePlaybackController.new,
      isAutoDispose: true,
    );

/// 随机播放控制器。
///
/// 管理视频播放列表状态，播放列表来自活动媒体会话的递归扫描；
/// 播放项以相对路径标识，不在此处拼接任何 URL。
/// 这是页面级 auto-dispose 会话，不保活；离开媒体页面后重建为 Idle。
class ShufflePlaybackController extends Notifier<ShufflePlaybackState> {
  int _operationGeneration = 0;
  int _sessionGeneration = 0;

  @override
  ShufflePlaybackState build() => const ShufflePlaybackIdle();

  final _random = Random();

  /// 从活动会话递归获取视频列表、shuffle、设为 Active。
  ///
  /// 返回第一个视频的相对路径，或 null（会话不可用 / 无视频 / 请求失败）。
  Future<String?> startShuffle(String directoryPath) async {
    final session = ref.read(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) return null;
    _sessionGeneration = session.generation;
    final generation = ++_operationGeneration;
    state = const ShufflePlaybackLoading();

    try {
      final list = await session.library.listVideosRecursively(directoryPath);
      if (!_isCurrent(session, generation)) return null;

      if (list.isEmpty) {
        state = const ShufflePlaybackIdle();
        return null;
      }

      // Fisher-Yates shuffle（只对 ≥2 个项有意义）
      if (list.length >= 2) list.shuffle(_random);

      if (!_isCurrent(session, generation)) return null;

      state = ShufflePlaybackActive(
        playlist: list,
        currentIndex: 0,
        directoryPath: directoryPath,
      );

      return list.first.relativePath;
    } on MediaLibraryFailure {
      if (!_isCurrent(session, generation)) return null;
      state = const ShufflePlaybackIdle();
      return null;
    } catch (_) {
      // 未知异常同样回 Idle：不把底层细节泄露给用户
      if (!_isCurrent(session, generation)) return null;
      state = const ShufflePlaybackIdle();
      return null;
    }
  }

  /// 播放下一个视频。返回新位置视频的相对路径，若已是最后一个则返回 null。
  String? playNext() {
    final s = state;
    if (s is! ShufflePlaybackActive) return null;
    if (s.isLast) return null;
    final newIndex = s.currentIndex + 1;
    state = ShufflePlaybackActive(
      playlist: s.playlist,
      currentIndex: newIndex,
      directoryPath: s.directoryPath,
    );
    return s.playlist[newIndex].relativePath;
  }

  /// 播放上一个视频。返回新位置视频的相对路径，若已是第一个则返回 null。
  String? playPrevious() {
    final s = state;
    if (s is! ShufflePlaybackActive) return null;
    if (s.isFirst) return null;
    final newIndex = s.currentIndex - 1;
    state = ShufflePlaybackActive(
      playlist: s.playlist,
      currentIndex: newIndex,
      directoryPath: s.directoryPath,
    );
    return s.playlist[newIndex].relativePath;
  }

  /// 播放器退出回调。若当前为最后一个视频则重置为 Idle。
  void onPlayerExited() {
    final s = state;
    if (s is ShufflePlaybackActive && s.isLast) {
      state = const ShufflePlaybackIdle();
    }
  }

  /// 目录变化时若与当前播放列表目录不一致则清空。
  void clearIfDirectoryChanged(String newPath) {
    final s = state;
    if (s is ShufflePlaybackActive && s.directoryPath != newPath) {
      state = const ShufflePlaybackIdle();
    }
  }

  /// 手动重置为 Idle。
  void reset() {
    _operationGeneration++;
    state = const ShufflePlaybackIdle();
  }

  bool _isCurrent(MediaLibrarySessionActive captured, int operation) {
    final current = ref.read(mediaLibrarySessionProvider);
    return ref.mounted &&
        operation == _operationGeneration &&
        current is MediaLibrarySessionActive &&
        current.generation == captured.generation &&
        captured.generation == _sessionGeneration;
  }
}
