import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/http/http_client_provider.dart';
import '../data/media_directory_scanner.dart'; // VideoItem 在此定义
import 'media_browser_controller.dart';

// ── 状态定义 ────────────────────────────────────────────

sealed class ShufflePlaybackState {
  const ShufflePlaybackState();
}

class ShufflePlaybackIdle extends ShufflePlaybackState {
  const ShufflePlaybackIdle();
}

class ShufflePlaybackLoading extends ShufflePlaybackState {
  const ShufflePlaybackLoading();
}

class ShufflePlaybackActive extends ShufflePlaybackState {
  final List<VideoItem> playlist;
  final int currentIndex;
  final String directoryPath;

  const ShufflePlaybackActive({
    required this.playlist,
    required this.currentIndex,
    required this.directoryPath,
  });

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
);

/// 随机播放控制器。
///
/// 管理视频播放列表状态，协调服务端请求和客户端 shuffle。
/// 通过 [mediaBrowserControllerProvider] 获取服务端地址构建 URL。
class ShufflePlaybackController extends Notifier<ShufflePlaybackState> {
  http.Client get _httpClient => ref.read(httpClientProvider);

  @override
  ShufflePlaybackState build() => const ShufflePlaybackIdle();

  final _random = Random();

  /// 从服务端获取视频列表、shuffle、设为 Active。
  ///
  /// 返回第一个视频的 URL，或 null（0 个视频 / 请求失败）。
  Future<String?> startShuffle(String directoryPath) async {
    final browserState = ref.read(mediaBrowserControllerProvider);
    final server = browserState.server;
    if (server == null) return null;

    state = const ShufflePlaybackLoading();

    try {
      final encodedPath = encodeMediaPath(directoryPath);
      final url = Uri.parse(
        'http://${server.ip}:${server.httpPort}/api/media/videos/recursive/$encodedPath',
      );
      final response = await _httpClient.get(url).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        state = const ShufflePlaybackIdle();
        return null;
      }

      final list = (jsonDecode(response.body) as List)
          .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
          .toList();

      if (list.isEmpty) {
        state = const ShufflePlaybackIdle();
        return null;
      }

      // Fisher-Yates shuffle（只对 ≥2 个项有意义）
      if (list.length >= 2) list.shuffle(_random);

      state = ShufflePlaybackActive(
        playlist: list,
        currentIndex: 0,
        directoryPath: directoryPath,
      );

      return buildVideoUrl(list.first.relativePath);
    } catch (_) {
      state = const ShufflePlaybackIdle();
      return null;
    }
  }

  /// 播放下一个视频。返回视频 URL，若已是最后一个则返回 null。
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
    return buildVideoUrl(s.playlist[newIndex].relativePath);
  }

  /// 播放上一个视频。返回视频 URL，若已是第一个则返回 null。
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
    return buildVideoUrl(s.playlist[newIndex].relativePath);
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
    state = const ShufflePlaybackIdle();
  }

  /// 构建视频播放 URL。
  String? buildVideoUrl(String relativePath) {
    final server = ref.read(mediaBrowserControllerProvider).server;
    if (server == null) return null;
    final encoded = encodeMediaPath(relativePath);
    return 'http://${server.ip}:${server.httpPort}/api/media/video/$encoded';
  }
}
