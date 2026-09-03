import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/fake_media_library.dart';
import '../helpers/media_test_helpers.dart';

List<VideoItem> _videos(int count) => List.generate(
  count,
  (i) => VideoItem(name: 'v$i.mp4', relativePath: '/dir/v$i.mp4'),
);

/// listVideosRecursively 抛未知异常的库：验证不泄露原始错误。
final class _BoomVideoLibrary implements MediaLibrary {
  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) async {
    throw StateError('boom-videos');
  }

  @override
  Future<List<FileItem>> listDirectory(String relativePath) =>
      throw UnimplementedError();

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) =>
      throw UnimplementedError();

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) =>
      throw UnimplementedError();
}

void main() {
  group('ShufflePlaybackController.startShuffle', () {
    test('startShuffle loads videos and returns first relative path', () async {
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/视频'] = const [
          VideoItem(name: 'only.mp4', relativePath: '/视频/only.mp4'),
        ];
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);
      final path = await container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/视频');
      expect(path, '/视频/only.mp4');
      expect(library.listVideosRecursivelyCalls, ['/视频']);
    });

    test('会话未激活 → 返回 null，保持 Idle', () async {
      final container = createMediaLibraryTestContainer(FakeMediaLibrary());
      final result = await container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('空列表 → 返回 null，回到 Idle', () async {
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/dir'] = const [];
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final result = await container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('库失败 → 返回 null，回到 Idle 且不泄露原始错误', () async {
      final library = FakeMediaLibrary()
        ..videoFailure = const MediaLibraryFailure(
          MediaLibraryFailureCode.networkUnavailable,
          '无法连接媒体服务',
        );
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final result = await container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('未知异常 → 返回 null，回到 Idle 且不泄露原始错误', () async {
      final container = createMediaLibraryTestContainerWith(
        _BoomVideoLibrary(),
      );
      await activateTestMediaSession(container);

      final result = await container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/dir');
      expect(result, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackIdle>(),
      );
    });

    test('reset 后忽略已失效视频列表响应', () async {
      final library = FakeMediaLibrary()
        ..pendingVideos = Completer<List<VideoItem>>();
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );
      final pending = controller.startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        const ShufflePlaybackLoading(),
      );

      controller.reset();
      library.pendingVideos!.complete(_videos(1));

      expect(await pending, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        const ShufflePlaybackIdle(),
      );
    });

    test('会话替换后旧会话的挂起列表不进入播放', () async {
      final library = FakeMediaLibrary()
        ..pendingVideos = Completer<List<VideoItem>>();
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final pending = container
          .read(shufflePlaybackControllerProvider.notifier)
          .startShuffle('/dir');
      expect(
        container.read(shufflePlaybackControllerProvider),
        isA<ShufflePlaybackLoading>(),
      );

      // 激活会话 B：代数递增，A 的挂起请求随即过期
      await container
          .read(mediaLibrarySessionProvider.notifier)
          .activate(
            RemoteMediaLibrarySource(Uri.parse('http://192.168.1.6:8080')),
          );
      library.pendingVideos!.complete(_videos(1));

      expect(await pending, isNull);
      expect(
        container.read(shufflePlaybackControllerProvider),
        isNot(isA<ShufflePlaybackActive>()),
      );
    });
  });

  group('ShufflePlaybackController.playNext / playPrevious', () {
    test('播放导航生命周期：非活跃返回 null，返回相对路径，首位/末尾边界正确', () async {
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/dir'] = _videos(3);
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        shufflePlaybackControllerProvider.notifier,
      );

      // 非活跃状态：next/previous 均返回 null
      expect(controller.playNext(), isNull);
      expect(controller.playPrevious(), isNull);

      await controller.startShuffle('/dir');
      final active = container.read(
        shufflePlaybackControllerProvider,
      ) as ShufflePlaybackActive;

      // 首位：previous 返回 null
      expect(controller.playPrevious(), isNull);

      // next 推进到 index 1，返回新位置的相对路径
      expect(controller.playNext(), active.playlist[1].relativePath);
      var state = container.read(
        shufflePlaybackControllerProvider,
      ) as ShufflePlaybackActive;
      expect(state.currentIndex, 1);

      // previous 回到 index 0，返回新位置的相对路径
      expect(controller.playPrevious(), state.playlist[0].relativePath);
      state = container.read(
        shufflePlaybackControllerProvider,
      ) as ShufflePlaybackActive;
      expect(state.currentIndex, 0);

      // 推进到末尾：next 返回 null
      controller.playNext();
      controller.playNext();
      expect(controller.playNext(), isNull);
    });
  });

  group('ShufflePlaybackController.onPlayerExited', () {
    test('退出生命周期：非末尾保持 Active，末尾退出回到 Idle', () async {
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/dir'] = _videos(3);
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

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
        (container.read(
          shufflePlaybackControllerProvider,
        ) as ShufflePlaybackActive).isLast,
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
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/dir'] = _videos(3);
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

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
      final library = FakeMediaLibrary()
        ..recursiveVideoResults['/dir'] = _videos(3);
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

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
}
