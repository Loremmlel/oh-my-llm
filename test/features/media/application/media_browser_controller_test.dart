import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/media_test_helpers.dart';

void main() {
  group('MediaBrowserState', () {
    test('初始状态', () {
      const state = MediaBrowserState();
      expect(state.currentPath, '/');
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.server, isNull);
      expect(state.isAtRoot, isTrue);
      expect(state.canGoBack, isFalse);
    });

    test('isAtRoot', () {
      expect(const MediaBrowserState(currentPath: '/').isAtRoot, isTrue);
      expect(const MediaBrowserState(currentPath: '').isAtRoot, isTrue);
      expect(const MediaBrowserState(currentPath: '/sub').isAtRoot, isFalse);
    });

    test('canGoBack', () {
      expect(const MediaBrowserState(pathHistory: []).canGoBack, isFalse);
      expect(const MediaBrowserState(pathHistory: ['/']).canGoBack, isTrue);
    });

    test('copyWith 保留未指定字段', () {
      const state = MediaBrowserState(
        currentPath: '/sub',
        items: [FileItem(name: 'a.mp4', isDirectory: false, sizeBytes: 100, relativePath: '/a.mp4')],
      );
      final updated = state.copyWith(isLoading: true);
      expect(updated.currentPath, '/sub');
      expect(updated.items.length, 1);
      expect(updated.isLoading, isTrue);
    });
  });

  group('MediaBrowserController', () {
    test('build() 初始状态', () {
      final container = createMediaTestContainer(httpClient: okMockClient('[]'));
      addTearDown(container.dispose);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/');
      expect(state.items, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.canGoBack, isFalse);
    });

    test('initWithServer 设置 server 并加载根目录', () async {
      final items = [
        const FileItem(name: 'test.mp4', isDirectory: false, sizeBytes: 100, relativePath: '/test.mp4'),
      ];
      final container = createMediaTestContainer(httpClient: okMockClient(fileListJson(items)));
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.server, testServer);
      expect(state.items, isNotEmpty);
    });

    test('loadDirectory server null → errorMessage', () async {
      final container = createMediaTestContainer(httpClient: okMockClient('[]'));
      addTearDown(container.dispose);

      final controller = container.read(mediaBrowserControllerProvider.notifier);
      await controller.loadDirectory('/');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, '未连接到服务端');
      expect(state.isLoading, isFalse);
    });

    test('loadDirectory HTTP 200 → items 更新', () async {
      final items = [
        const FileItem(name: 'a.mp4', isDirectory: false, sizeBytes: 100, relativePath: '/a.mp4'),
        const FileItem(name: 'sub', isDirectory: true, sizeBytes: 0, relativePath: '/sub'),
      ];
      final container = createMediaTestContainer(httpClient: okMockClient(fileListJson(items)));
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.items.length, 2);
      expect(state.currentPath, '/');
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('loadDirectory HTTP 非 200 → errorMessage', () async {
      final container = createMediaTestContainer(httpClient: statusMockClient(500));
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('loadDirectory 网络异常 → 包含错误信息', () async {
      final container = createMediaTestContainer(httpClient: throwingMockClient());
      addTearDown(container.dispose);

      await initBrowserAndWait(container);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoading, isFalse);
    });

    test('navigateTo 成功 → pathHistory 推入', () async {
      final rootItems = [
        const FileItem(name: 'sub', isDirectory: true, sizeBytes: 0, relativePath: '/sub'),
      ];
      final subItems = [
        const FileItem(name: 'a.mp4', isDirectory: false, sizeBytes: 100, relativePath: '/sub/a.mp4'),
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

      final controller = container.read(mediaBrowserControllerProvider.notifier);
      await controller.navigateTo('/sub');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/sub');
      expect(state.pathHistory, ['/']);
      expect(state.canGoBack, isTrue);
    });

    test('navigateTo 失败 → pathHistory 不变', () async {
      final container = createMediaTestContainer(httpClient: statusMockClient(500));
      addTearDown(container.dispose);

      await initBrowserAndWait(container);

      final controller = container.read(mediaBrowserControllerProvider.notifier);
      await controller.navigateTo('/sub');
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.pathHistory, isEmpty);
    });

    test('goBack 有历史 → 返回 true 并恢复路径', () async {
      final rootItems = [
        const FileItem(name: 'sub', isDirectory: true, sizeBytes: 0, relativePath: '/sub'),
      ];
      final client = MockClient((request) async {
        return http.Response(fileListJson(rootItems), 200);
      });

      final container = createMediaTestContainer(httpClient: client);
      addTearDown(container.dispose);

      await initBrowserAndWait(container);

      final controller = container.read(mediaBrowserControllerProvider.notifier);
      await controller.navigateTo('/sub');
      final result = await controller.goBack();
      expect(result, isTrue);
      final state = container.read(mediaBrowserControllerProvider);
      expect(state.currentPath, '/');
    });

    test('goBack 无历史 → 返回 false', () async {
      final container = createMediaTestContainer(httpClient: okMockClient('[]'));
      addTearDown(container.dispose);

      final controller = container.read(mediaBrowserControllerProvider.notifier);
      final result = await controller.goBack();
      expect(result, isFalse);
    });
  });
}
