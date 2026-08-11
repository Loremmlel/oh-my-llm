import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/media_test_helpers.dart';

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

      // 初始公开状态即 build() 返回值：根目录、空列表、未加载、无错误、无服务端
      final initial = MediaBrowserState();
      expect(initial.currentPath, '/');
      expect(initial.items, isEmpty);
      expect(initial.isLoading, isFalse);
      expect(initial.errorMessage, isNull);
      expect(initial.server, isNull);
    });
  });

  group('MediaBrowserController', () {
    test('reset 后忽略已失效请求的响应', () async {
      final responseCompleter = Completer<http.Response>();
      final container = createMediaTestContainer(
        httpClient: MockClient((_) => responseCompleter.future),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      controller.initWithServer(testServer);
      expect(container.read(mediaBrowserControllerProvider).isLoading, isTrue);

      controller.reset();
      responseCompleter.complete(
        http.Response(
          fileListJson([
            const FileItem(
              name: 'stale.mp4',
              isDirectory: false,
              sizeBytes: 1,
              relativePath: '/stale.mp4',
            ),
          ]),
          200,
        ),
      );
      await responseCompleter.future;
      await Future<void>.value();

      expect(
        container.read(mediaBrowserControllerProvider),
        MediaBrowserState(),
      );
    });

    test('媒体浏览页面会话在观察者释放后重建为空状态', () async {
      final container = createMediaTestContainer(
        httpClient: okMockClient('[]'),
        retainBrowserListener: false,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        mediaBrowserControllerProvider,
        (_, _) {},
      );
      await initBrowserAndWait(container);

      subscription.close();
      await container.pump();

      expect(container.exists(mediaBrowserControllerProvider), isFalse);
      expect(
        container.read(mediaBrowserControllerProvider),
        MediaBrowserState(),
      );
    });

    test('initWithServer 设置 server 并加载根目录成功', () async {
      final items = [
        const FileItem(
          name: 'a.mp4',
          isDirectory: false,
          sizeBytes: 100,
          relativePath: '/a.mp4',
        ),
        const FileItem(
          name: 'sub',
          isDirectory: true,
          sizeBytes: 0,
          relativePath: '/sub',
        ),
      ];
      final container = createMediaTestContainer(
        httpClient: okMockClient(fileListJson(items)),
      );
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.server, testServer);
      expect(state.currentPath, '/');
      expect(state.items, hasLength(2));
      expect(state.items.map((i) => i.name), ['a.mp4', 'sub']);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('loadDirectory server null → errorMessage', () async {
      final container = createMediaTestContainer(
        httpClient: okMockClient('[]'),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      await controller.loadDirectory('/');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, '未连接到服务端');
      expect(state.isLoading, isFalse);
    });

    test('loadDirectory HTTP 非 200 → errorMessage', () async {
      final container = createMediaTestContainer(
        httpClient: statusMockClient(500),
      );
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('loadDirectory 网络异常 → 包含错误信息', () async {
      final container = createMediaTestContainer(
        httpClient: throwingMockClient(),
      );
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('navigateTo 成功后 goBack 恢复根目录', () async {
      final rootItems = [
        const FileItem(
          name: 'sub',
          isDirectory: true,
          sizeBytes: 0,
          relativePath: '/sub',
        ),
      ];
      final subItems = [
        const FileItem(
          name: 'a.mp4',
          isDirectory: false,
          sizeBytes: 100,
          relativePath: '/sub/a.mp4',
        ),
      ];
      final client = MockClient((request) async {
        if (request.url.path.contains('sub')) {
          return http.Response(fileListJson(subItems), 200);
        }
        return http.Response(fileListJson(rootItems), 200);
      });

      final container = createMediaTestContainer(httpClient: client);
      addTearDown(container.dispose);

      await initBrowserAndWait(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );

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
      final container = createMediaTestContainer(
        httpClient: statusMockClient(500),
      );
      addTearDown(container.dispose);

      await initBrowserAndWait(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      await controller.navigateTo('/sub');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.pathHistory, isEmpty);
    });

    test('goBack 无历史 → 返回 false', () async {
      final container = createMediaTestContainer(
        httpClient: okMockClient('[]'),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      final result = await controller.goBack();
      expect(result, isFalse);
    });
  });
}
