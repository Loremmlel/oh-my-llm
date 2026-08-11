import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/media_test_helpers.dart';

List<VideoItem> _videos(int count) => List.generate(
  count,
  (i) => VideoItem(name: 'v$i.mp4', relativePath: '/dir/v$i.mp4'),
);

String _videoListJson(List<VideoItem> items) =>
    jsonEncode(items.map((v) => v.toJson()).toList());

ProviderContainer _createContainer({
  required http.Client httpClient,
  MediaBrowserState? browserState,
}) {
  return ProviderContainer(
    overrides: [
      peerHttpClientProvider.overrideWithValue(httpClient),
      mediaBrowserControllerProvider.overrideWith(
        () => _StubBrowserController(browserState ?? MediaBrowserState()),
      ),
    ],
  );
}

class _StubBrowserController extends MediaBrowserController {
  final MediaBrowserState _initial;
  _StubBrowserController(this._initial);

  @override
  MediaBrowserState build() => _initial;
}

void main() {
  group('ShufflePlaybackController.startShuffle', () {
    test('reset 后忽略已失效视频列表响应', () async {
      final responseCompleter = Completer<http.Response>();
      final container = _createContainer(
        httpClient: MockClient((_) => responseCompleter.future),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final pending = controller.startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        const ShufflePlaybackLoading(),
      );

      controller.reset();
      responseCompleter.complete(
        http.Response(_videoListJson(_videos(1)), 200),
      );

      expect(await pending, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        const ShufflePlaybackIdle(),
      );
    });

    test('server 为 null → 返回 null，保持 Idle', () async {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: MediaBrowserState(),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('HTTP 200 + 空列表 → 返回 null，回到 Idle', () async {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('HTTP 200 + 有视频 → 返回 URL，状态 Active', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final result = await controller.startShuffle('/dir');
      expect(result, isNotNull);
      expect(result, contains('/api/media/video/'));
      final state = container.read(shufflePlaybackControllerProvider);
      expect(state, isA<ShufflePlaybackActive>());
      final active = state as ShufflePlaybackActive;
      expect(active.totalCount, 3);
      expect(active.directoryPath, '/dir');
    });

    test('HTTP 非 200 → 回到 Idle', () async {
      final container = _createContainer(
        httpClient: statusMockClient(500),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('网络异常 → 回到 Idle', () async {
      final container = _createContainer(
        httpClient: throwingMockClient(),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    // Fisher-Yates 对 20 项 shuffle 后与原始顺序完全相同的概率为 1/20! ≈ 4×10⁻¹⁹，
    // 运行 5 次至少一次不同的概率 ≈ 1 − (1/20!)⁵ ≈ 1。概率性测试在此规模下足够可靠。
    test('列表被 shuffle（多视频时顺序改变）', () async {
      final videos = _videos(20);
      var wasShuffled = false;
      for (int attempt = 0; attempt < 5; attempt++) {
        final container = _createContainer(
          httpClient: okMockClient(_videoListJson(videos)),
          browserState: MediaBrowserState(server: testServer),
        );

        final controller = container.read(
          shufflePlaybackControllerProvider.notifier,
        );
        await controller.startShuffle('/dir');
        final state =
            container.read(shufflePlaybackControllerProvider)
                as ShufflePlaybackActive;
        final originalPaths = videos.map((v) => v.relativePath).toList();
        final shuffledPaths = state.playlist
            .map((v) => v.relativePath)
            .toList();
        if (shuffledPaths.join(',') != originalPaths.join(',')) {
          wasShuffled = true;
        }
        container.dispose();
      }
      expect(wasShuffled, isTrue);
    });
  });

  group('ShufflePlaybackController.playNext / playPrevious', () {
    test('播放导航生命周期：非活跃返回 null，首位/末尾边界正确', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );

      // 非活跃状态：next/previous 均返回 null
      expect(controller.playNext(), isNull);
      expect(controller.playPrevious(), isNull);

      await controller.startShuffle('/dir');

      // 首位：previous 返回 null
      expect(controller.playPrevious(), isNull);

      // next 推进到 index 1
      expect(controller.playNext(), isNotNull);
      var state =
          container.read(shufflePlaybackControllerProvider)
              as ShufflePlaybackActive;
      expect(state.currentIndex, 1);

      // previous 回到 index 0
      expect(controller.playPrevious(), isNotNull);
      state =
          container.read(shufflePlaybackControllerProvider)
              as ShufflePlaybackActive;
      expect(state.currentIndex, 0);

      // 推进到末尾：next 返回 null
      controller.playNext();
      controller.playNext();
      expect(controller.playNext(), isNull);
    });
  });

  group('ShufflePlaybackController.onPlayerExited', () {
    test('退出生命周期：非末尾保持 Active，末尾退出回到 Idle', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      await controller.startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackActive>(),
      );

      // 非末尾退出：保持 Active
      controller.onPlayerExited();
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackActive>(),
      );

      // 推进到末尾后退出：回到 Idle
      controller.playNext();
      controller.playNext();
      expect(
        (container.read(shufflePlaybackControllerProvider)
                as ShufflePlaybackActive)
            .isLast,
        isTrue,
      );
      controller.onPlayerExited();
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });
  });

  group('ShufflePlaybackController.clearIfDirectoryChanged', () {
    test('目录变更生命周期：相同目录保持 Active，不同目录回到 Idle', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      await controller.startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackActive>(),
      );

      // 相同目录：保持 Active
      controller.clearIfDirectoryChanged('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackActive>(),
      );

      // 不同目录：回到 Idle
      controller.clearIfDirectoryChanged('/other');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });
  });

  group('ShufflePlaybackController.reset', () {
    test('从 Active 回到 Idle', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      await controller.startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackActive>(),
      );
      controller.reset();
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });
  });

  group('ShufflePlaybackController.buildVideoUrl', () {
    test('buildVideoUrl 矩阵：null 服务端/英文路径/中文路径编码', () {
      for (final (:name, :server, :path, :expected) in [
        (
          name: 'server 为 null 返回 null',
          server: null,
          path: '/test.mp4',
          expected: null,
        ),
        (
          name: '英文路径正确拼接',
          server: testServer,
          path: '/test.mp4',
          expected: 'http://192.168.1.5:8080/api/media/video/test.mp4',
        ),
        (
          name: '中文路径正确编码',
          server: testServer,
          path: '/妹妹/视频.mp4',
          expected:
              'http://192.168.1.5:8080/api/media/video/'
              '%E5%A6%B9%E5%A6%B9/%E8%A7%86%E9%A2%91.mp4',
        ),
      ]) {
        final container = _createContainer(
          httpClient: okMockClient('[]'),
          browserState: MediaBrowserState(server: server),
        );
        addTearDown(container.dispose);

        final controller = container.read(
          shufflePlaybackControllerProvider.notifier,
        );
        expect(controller.buildVideoUrl(path), expected, reason: 'case: $name');
      }
    });
  });
}
