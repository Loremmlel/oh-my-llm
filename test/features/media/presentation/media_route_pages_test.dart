import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/presentation/pages/image_viewer_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';

import '../../../helpers/test_harness.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

FileItem _image(String path) => FileItem(
  name: path.split('/').last,
  isDirectory: false,
  sizeBytes: 1,
  relativePath: path,
);

/// 恢复页依赖 GoRouter.of，必须由 GoRouter 承载才能渲染。
GoRouter _recoveryRouter(Widget page) {
  return GoRouter(
    initialLocation: '/media',
    routes: [GoRoute(path: '/media', builder: (context, state) => page)],
  );
}

void main() {
  testWidgets('当前目录两张图片，target 为第二张时画廊从 2 / 2 开始', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_image('/相册/第一张.jpg'), _image('/相册/第二张.jpg')],
            ),
          ),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/第二张.jpg'),
    );

    // 计数器直接显示（无网络图片加载阻塞 build）
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });

  testWidgets('target 不在当前 items 时降级单图且不崩溃', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(server: testServer, items: const []),
          ),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/不存在.jpg'),
    );

    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () =>
              FakeMediaBrowserController(MediaBrowserState(server: testServer)),
        ),
      ],
      router: _recoveryRouter(const MediaImageRoutePage(relativePath: null)),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('图片扩展名不匹配显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: _recoveryRouter(
        const MediaImageRoutePage(relativePath: '/a/readme.txt'),
      ),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('server 缺失显示媒体会话已失效', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(MediaBrowserState()),
        ),
      ],
      router: _recoveryRouter(
        const MediaImageRoutePage(relativePath: '/相册/猫.jpg'),
      ),
    );

    expect(find.text('媒体会话已失效'), findsOneWidget);
  });

  testWidgets('视频 path 合法时通过共享 fake 初始化并显示文件名', (tester) async {
    final fake = FakeVideoPlayerController();
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () =>
              FakeMediaBrowserController(MediaBrowserState(server: testServer)),
        ),
      ],
      child: MediaVideoRoutePage(
        relativePath: '/视频/demo.mp4',
        controllerFactory: (uri) => fake,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.playCallCount, greaterThanOrEqualTo(1));
    expect(find.text('demo.mp4'), findsOneWidget);
    expect(find.byType(VideoPlayerPage), findsOneWidget);
  });

  testWidgets('视频 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () =>
              FakeMediaBrowserController(MediaBrowserState(server: testServer)),
        ),
      ],
      router: _recoveryRouter(const MediaVideoRoutePage(relativePath: null)),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('视频扩展名不匹配显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: _recoveryRouter(
        const MediaVideoRoutePage(relativePath: '/a/readme.txt'),
      ),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('恢复页按钮 pop 或 go 回 /sync', (tester) async {
    final prefs = await _testPrefs();
    final router = GoRouter(
      initialLocation: '/sync/media/image',
      routes: [
        GoRoute(
          path: '/sync',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('同步落点'))),
          routes: [
            GoRoute(
              path: 'media/image',
              builder: (context, state) =>
                  const MediaImageRoutePage(relativePath: null),
            ),
          ],
        ),
      ],
    );
    await pumpTestApp(tester, preferences: prefs, router: router);

    expect(find.text('返回局域网同步'), findsOneWidget);

    // 无父 route 可 pop（deep link 直达）→ 点击后 go 回 /sync。
    await tester.tap(find.text('返回局域网同步'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('同步落点'), findsOneWidget);
  });
}
