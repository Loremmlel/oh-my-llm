import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/media_test_helpers.dart';

List<VideoItem> _videos(int count) => List.generate(
      count,
      (i) => VideoItem(name: 'v$i.mp4', relativePath: '/dir/v$i.mp4'),
    );

String _videoListJson(List<VideoItem> items) => jsonEncode(
      items.map((v) => v.toJson()).toList(),
    );

ProviderContainer _createContainer({
  required http.Client httpClient,
  MediaBrowserState browserState = const MediaBrowserState(),
}) {
  return ProviderContainer(
    overrides: [
      httpClientProvider.overrideWithValue(
        CustomHeadersHttpClient(httpClient, {}),
      ),
      mediaBrowserControllerProvider
          .overrideWith(() => _StubBrowserController(browserState)),
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
    test('server 为 null → 返回 null，保持 Idle', () async {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    test('HTTP 200 + 空列表 → 返回 null，回到 Idle', () async {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    test('HTTP 200 + 有视频 → 返回 URL，状态 Active', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
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
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    test('网络异常 → 回到 Idle', () async {
      final container = _createContainer(
        httpClient: throwingMockClient(),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final result = await controller.startShuffle('/dir');
      expect(result, isNull);
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    // Fisher-Yates 对 20 项 shuffle 后与原始顺序完全相同的概率为 1/20! ≈ 4×10⁻¹⁹，
    // 运行 5 次至少一次不同的概率 ≈ 1 − (1/20!)⁵ ≈ 1。概率性测试在此规模下足够可靠。
    test('列表被 shuffle（多视频时顺序改变）', () async {
      final videos = _videos(20);
      var wasShuffled = false;
      for (int attempt = 0; attempt < 5; attempt++) {
        final container = _createContainer(
          httpClient: okMockClient(_videoListJson(videos)),
          browserState: const MediaBrowserState(server: testServer),
        );

        final controller =
            container.read(shufflePlaybackControllerProvider.notifier);
        await controller.startShuffle('/dir');
        final state = container.read(shufflePlaybackControllerProvider)
            as ShufflePlaybackActive;
        final originalPaths = videos.map((v) => v.relativePath).toList();
        final shuffledPaths = state.playlist.map((v) => v.relativePath).toList();
        if (shuffledPaths.join(',') != originalPaths.join(',')) {
          wasShuffled = true;
        }
        container.dispose();
      }
      expect(wasShuffled, isTrue);
    });
  });

  group('ShufflePlaybackController.playNext / playPrevious', () {
    test('非活跃状态 → 返回 null', () {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      expect(controller.playNext(), isNull);
      expect(controller.playPrevious(), isNull);
    });

    test('playNext 非末尾 → 返回 URL，index+1', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      final url = controller.playNext();
      expect(url, isNotNull);
      final state = container.read(shufflePlaybackControllerProvider)
          as ShufflePlaybackActive;
      expect(state.currentIndex, 1);
    });

    test('playNext 已末尾 → 返回 null', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      controller.playNext();
      controller.playNext();
      expect(controller.playNext(), isNull);
    });

    test('playPrevious 非首位 → 返回 URL，index-1', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      controller.playNext();
      final url = controller.playPrevious();
      expect(url, isNotNull);
      final state = container.read(shufflePlaybackControllerProvider)
          as ShufflePlaybackActive;
      expect(state.currentIndex, 0);
    });

    test('playPrevious 已首位 → 返回 null', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      expect(controller.playPrevious(), isNull);
    });
  });

  group('ShufflePlaybackController.onPlayerExited', () {
    test('末尾视频退出 → 回到 Idle', () async {
      final videos = _videos(1);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      final state = container.read(shufflePlaybackControllerProvider);
      expect(state, isA<ShufflePlaybackActive>());
      expect((state as ShufflePlaybackActive).isLast, isTrue);
      controller.onPlayerExited();
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    test('非末尾视频退出 → 保持 Active', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      controller.onPlayerExited();
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackActive>());
    });
  });

  group('ShufflePlaybackController.clearIfDirectoryChanged', () {
    test('目录不同 → 回到 Idle', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackActive>());
      controller.clearIfDirectoryChanged('/other');
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });

    test('目录相同 → 保持 Active', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      controller.clearIfDirectoryChanged('/dir');
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackActive>());
    });
  });

  group('ShufflePlaybackController.reset', () {
    test('从 Active 回到 Idle', () async {
      final videos = _videos(3);
      final container = _createContainer(
        httpClient: okMockClient(_videoListJson(videos)),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      await controller.startShuffle('/dir');
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackActive>());
      controller.reset();
      expect(container.read(shufflePlaybackControllerProvider),
          isA<ShufflePlaybackIdle>());
    });
  });

  group('ShufflePlaybackController.buildVideoUrl', () {
    test('server null → 返回 null', () {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      expect(controller.buildVideoUrl('/test.mp4'), isNull);
    });

    test('有 server → 正确拼接 URL', () {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final url = controller.buildVideoUrl('/test.mp4');
      expect(url, 'http://192.168.1.5:8080/api/media/video/test.mp4');
    });

    test('中文路径正确编码', () {
      final container = _createContainer(
        httpClient: okMockClient('[]'),
        browserState: const MediaBrowserState(server: testServer),
      );
      addTearDown(container.dispose);

      final controller =
          container.read(shufflePlaybackControllerProvider.notifier);
      final url = controller.buildVideoUrl('/妹妹/视频.mp4');
      expect(url, contains('%E5%A6%B9%E5%A6%B9'));
      expect(url, contains('%E8%A7%86%E9%A2%91'));
    });
  });
}
