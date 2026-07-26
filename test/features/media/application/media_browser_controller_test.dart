import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/media_test_helpers.dart';

void main() {
  group('MediaBrowserState', () {
    test('快照 item 和 history 输入并按值比较', () {
      final sourceItem = FileItem(
        name: 'test.mp4',
        isDirectory: false,
        sizeBytes: 100,
        relativePath: '/test.mp4',
      );
      final items = <FileItem>[sourceItem];
      final history = <String>['/'];
      final state = MediaBrowserState(items: items, pathHistory: history);
      items.clear();
      history.add('/movies');

      expect(state.items, [sourceItem]);
      expect(state.pathHistory, ['/']);
      expect(() => state.items.clear(), throwsUnsupportedError);
      expect(() => state.pathHistory.add('/x'), throwsUnsupportedError);
      expect(
        state,
        MediaBrowserState(
          items: [
            FileItem(
              name: 'test.mp4',
              isDirectory: false,
              sizeBytes: 100,
              relativePath: '/test.mp4',
            ),
          ],
          pathHistory: ['/'],
        ),
      );
    });

    test('初始状态', () {
      final state = MediaBrowserState();
      expect(state.currentPath, '/');
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.server, isNull);
      expect(state.isAtRoot, isTrue);
      expect(state.canGoBack, isFalse);
    });

    test('isAtRoot', () {
      expect(MediaBrowserState(currentPath: '/').isAtRoot, isTrue);
      expect(MediaBrowserState(currentPath: '').isAtRoot, isTrue);
      expect(MediaBrowserState(currentPath: '/sub').isAtRoot, isFalse);
    });

    test('canGoBack', () {
      expect(MediaBrowserState(pathHistory: []).canGoBack, isFalse);
      expect(MediaBrowserState(pathHistory: ['/']).canGoBack, isTrue);
    });

    test('copyWith 保留未指定字段', () {
      final state = MediaBrowserState(
        currentPath: '/sub',
        items: [
          FileItem(
            name: 'a.mp4',
            isDirectory: false,
            sizeBytes: 100,
            relativePath: '/a.mp4',
          ),
        ],
      );
      final updated = state.copyWith(isLoading: true);
      expect(updated.currentPath, '/sub');
      expect(updated.items.length, 1);
      expect(updated.isLoading, isTrue);
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

    test('build() 初始状态', () {
      final container = createMediaTestContainer(
        httpClient: okMockClient('[]'),
      );
      addTearDown(container.dispose);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/');
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.canGoBack, isFalse);
    });

    test('initWithServer 设置 server 并加载根目录', () async {
      final items = [
        const FileItem(
          name: 'test.mp4',
          isDirectory: false,
          sizeBytes: 100,
          relativePath: '/test.mp4',
        ),
      ];
      final container = createMediaTestContainer(
        httpClient: okMockClient(fileListJson(items)),
      );
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.server, testServer);
      expect(state.items, isNotEmpty);
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

    test('loadDirectory HTTP 200 → items 更新', () async {
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
      expect(state.items.length, 2);
      expect(state.currentPath, '/');
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
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

    test('navigateTo 成功 → pathHistory 推入', () async {
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
      await controller.navigateTo('/sub');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/sub');
      expect(state.pathHistory, ['/']);
      expect(state.canGoBack, isTrue);
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

    test('goBack 有历史 → 返回 true 并恢复路径', () async {
      final rootItems = [
        const FileItem(
          name: 'sub',
          isDirectory: true,
          sizeBytes: 0,
          relativePath: '/sub',
        ),
      ];
      final client = MockClient((request) async {
        return http.Response(fileListJson(rootItems), 200);
      });

      final container = createMediaTestContainer(httpClient: client);
      addTearDown(container.dispose);

      await initBrowserAndWait(container);

      final controller = container.read(
        mediaBrowserControllerProvider.notifier,
      );
      await controller.navigateTo('/sub');
      final result = await controller.goBack();
      expect(result, isTrue);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/');
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
