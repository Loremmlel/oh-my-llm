import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/fake_media_library.dart';
import '../helpers/media_test_helpers.dart';

/// listDirectory 抛未知异常的库：验证未知异常转为固定文案而不泄露细节。
final class _BoomDirectoryLibrary implements MediaLibrary {
  @override
  Future<List<FileItem>> listDirectory(String relativePath) async {
    throw StateError('boom-directory');
  }

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) =>
      throw UnimplementedError();

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) =>
      throw UnimplementedError();

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) =>
      throw UnimplementedError();
}

FileItem _file(String path) => FileItem(
  name: path.split('/').last,
  isDirectory: false,
  sizeBytes: 1,
  relativePath: path,
);

FileItem _dir(String path) => FileItem(
  name: path.split('/').last,
  isDirectory: true,
  sizeBytes: 0,
  relativePath: path,
);

void main() {
  group('MediaBrowserState', () {
    test('派生状态矩阵：初始/空路径/嵌套路径/历史记录', () {
      for (final (:name, :state, :expectedIsAtRoot, :expectedCanGoBack) in [
        (
          name: '初始状态',
          state: MediaBrowserState(),
          expectedIsAtRoot: true,
          expectedCanGoBack: false,
        ),
        (
          name: '空路径视为根目录',
          state: MediaBrowserState(currentPath: ''),
          expectedIsAtRoot: true,
          expectedCanGoBack: false,
        ),
        (
          name: '嵌套路径非根目录',
          state: MediaBrowserState(currentPath: '/sub'),
          expectedIsAtRoot: false,
          expectedCanGoBack: false,
        ),
        (
          name: '有历史记录可返回',
          state: MediaBrowserState(pathHistory: ['/']),
          expectedIsAtRoot: true,
          expectedCanGoBack: true,
        ),
      ]) {
        expect(state.isAtRoot, expectedIsAtRoot, reason: 'case: $name');
        expect(state.canGoBack, expectedCanGoBack, reason: 'case: $name');
      }

      // 初始公开状态即 build() 返回值：根目录、空列表、未加载、无错误
      final initial = MediaBrowserState();
      expect(initial.currentPath, '/');
      expect(initial.items, isEmpty);
      expect(initial.isLoading, isFalse);
      expect(initial.errorMessage, isNull);
    });
  });

  group('MediaBrowserController', () {
    test('active session loads root and never exposes server state', () async {
      const image = FileItem(
        name: '猫.jpg',
        isDirectory: false,
        sizeBytes: 1,
        relativePath: '/猫.jpg',
        hasThumbnail: true,
      );
      final library = FakeMediaLibrary()..directoryResults['/'] = [image];
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);
      await container
          .read(mediaBrowserControllerProvider.notifier)
          .initFromActiveSession();
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.items, [image]);
      expect(library.listDirectoryCalls, ['/']);
    });

    test('会话未激活时 initFromActiveSession 发布媒体会话不可用', () async {
      final container = createMediaLibraryTestContainer(FakeMediaLibrary());
      final loaded = await container
          .read(mediaBrowserControllerProvider.notifier)
          .initFromActiveSession();
      expect(loaded, isFalse);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, '媒体会话不可用');
      expect(state.isLoading, isFalse);
    });

    test('会话未激活时 loadDirectory 发布媒体会话不可用', () async {
      final container = createMediaLibraryTestContainer(FakeMediaLibrary());
      final loaded = await container
          .read(mediaBrowserControllerProvider.notifier)
          .loadDirectory('/');
      expect(loaded, isFalse);
      expect(
        container.read(mediaBrowserControllerProvider).errorMessage,
        '媒体会话不可用',
      );
    });

    test('reset 后忽略已失效请求的响应', () async {
      final library = FakeMediaLibrary()
        ..pendingDirectory = Completer<List<FileItem>>();
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      final pending = controller.initFromActiveSession();
      expect(container.read(mediaBrowserControllerProvider).isLoading, isTrue);

      controller.reset();
      library.pendingDirectory!.complete([_file('/stale.mp4')]);
      expect(await pending, isFalse);

      expect(
        container.read(mediaBrowserControllerProvider),
        MediaBrowserState(),
      );
    });

    test('媒体浏览页面会话在观察者释放后重建为空状态', () async {
      final container = ProviderContainer(
        overrides: [
          mediaLibraryFactoryProvider.overrideWithValue(
            FakeMediaLibraryFactory(FakeMediaLibrary()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sessionSubscription = container.listen(
        mediaLibrarySessionProvider,
        (_, _) {},
      );
      final browserSubscription = container.listen(
        mediaBrowserControllerProvider,
        (_, _) {},
      );
      await activateTestMediaSession(container);
      await container
          .read(mediaBrowserControllerProvider.notifier)
          .initFromActiveSession();

      browserSubscription.close();
      sessionSubscription.close();
      await container.pump();

      expect(container.exists(mediaBrowserControllerProvider), isFalse);
      expect(
        container.read(mediaBrowserControllerProvider),
        MediaBrowserState(),
      );
    });

    test('目录加载失败发布失败原因', () async {
      final library = FakeMediaLibrary()
        ..directoryFailure = const MediaLibraryFailure(
          MediaLibraryFailureCode.networkUnavailable,
          '无法连接媒体服务',
        );
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      await container
          .read(mediaBrowserControllerProvider.notifier)
          .initFromActiveSession();
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, '无法连接媒体服务');
      expect(state.isLoading, isFalse);
    });

    test('未知异常转为固定文案且不泄露原始错误', () async {
      final container = createMediaLibraryTestContainerWith(
        _BoomDirectoryLibrary(),
      );
      await activateTestMediaSession(container);

      await container
          .read(mediaBrowserControllerProvider.notifier)
          .initFromActiveSession();
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, '加载媒体目录失败');
      expect(state.errorMessage, isNot(contains('boom')));
    });

    test('navigateTo 成功后 goBack 恢复根目录', () async {
      final library = FakeMediaLibrary()
        ..directoryResults['/'] = [_dir('/sub')]
        ..directoryResults['/sub'] = [_file('/sub/a.mp4')];
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      await controller.initFromActiveSession();

      // 推入历史：导航进入子目录
      await controller.navigateTo('/sub');
      var state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/sub');
      expect(state.pathHistory, ['/']);
      expect(state.canGoBack, isTrue);

      // 弹出历史：goBack 恢复根目录
      final result = await controller.goBack();
      expect(result, isTrue);
      state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/');
      expect(state.pathHistory, isEmpty);
      expect(state.canGoBack, isFalse);
    });

    test('navigateTo 失败 → pathHistory 不变', () async {
      final library = FakeMediaLibrary()
        ..directoryResults['/'] = [_dir('/sub')];
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      await controller.initFromActiveSession();

      // 根目录加载成功后让后续目录请求失败
      library.directoryFailure = const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidPath,
        '媒体路径无效',
      );
      await controller.navigateTo('/sub');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.pathHistory, isEmpty);
      expect(state.errorMessage, '媒体路径无效');
    });

    test('goBack 无历史 → 返回 false', () async {
      final container = createMediaLibraryTestContainer(FakeMediaLibrary());
      await activateTestMediaSession(container);

      final result = await container
          .read(mediaBrowserControllerProvider.notifier)
          .goBack();
      expect(result, isFalse);
    });

    test('会话替换后旧会话的挂起列表不更新浏览器状态', () async {
      final library = FakeMediaLibrary()
        ..pendingDirectory = Completer<List<FileItem>>();
      final container = createMediaLibraryTestContainer(library);
      await activateTestMediaSession(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      final pendingLoad = controller.initFromActiveSession();
      expect(container.read(mediaBrowserControllerProvider).isLoading, isTrue);

      // 激活会话 B：代数递增，A 的挂起请求随即过期
      await container
          .read(mediaLibrarySessionProvider.notifier)
          .activate(
            RemoteMediaLibrarySource(Uri.parse('http://192.168.1.6:8080')),
          );
      library.pendingDirectory!.complete([_file('/stale.mp4')]);
      expect(await pendingLoad, isFalse);

      // A 的过期结果不得写入浏览器状态
      expect(container.read(mediaBrowserControllerProvider).items, isEmpty);
    });
  });
}
