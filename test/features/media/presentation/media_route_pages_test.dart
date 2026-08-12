import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../helpers/fake_media_library.dart';
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

/// 预激活会话的库：为图片/视频资源解析提供结果。
FakeMediaLibrary _libraryWithAssets() {
  return FakeMediaLibrary()
    ..assetResults[const MediaAssetRequest(
      kind: MediaAssetKind.image,
      relativePath: '/相册/第一张.jpg',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/image/相册/第一张.jpg'),
    )
    ..assetResults[const MediaAssetRequest(
      kind: MediaAssetKind.image,
      relativePath: '/相册/第二张.jpg',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/image/相册/第二张.jpg'),
    )
    ..assetResults[const MediaAssetRequest(
      kind: MediaAssetKind.image,
      relativePath: '/相册/不存在.jpg',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/image/相册/不存在.jpg'),
    )
    ..assetResults[const MediaAssetRequest(
      kind: MediaAssetKind.video,
      relativePath: '/视频/demo.mp4',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/video/视频/demo.mp4'),
    );
}

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
        mediaLibrarySessionProvider.overrideWith(
          () => PreActivatedMediaLibrarySessionController(_libraryWithAssets()),
        ),
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              items: [_image('/相册/第一张.jpg'), _image('/相册/第二张.jpg')],
            ),
          ),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/第二张.jpg'),
    );

    // 计数器直接显示（图片解码不阻塞 build）
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('target 不在当前 items 时降级单图且不崩溃', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaLibrarySessionProvider.overrideWith(
          () => PreActivatedMediaLibrarySessionController(_libraryWithAssets()),
        ),
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(MediaBrowserState(items: const [])),
        ),
      ],
      child: const MediaImageRoutePage(relativePath: '/相册/不存在.jpg'),
    );

    // 降级为单图查看：单图不显示计数器；测试环境 mock HTTP 恒 400，
    // 两帧后解码失败呈现错误文案
    await tester.pump();
    await tester.pump();
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
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

  testWidgets('会话未激活显示媒体会话已失效', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
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
        mediaLibrarySessionProvider.overrideWith(
          () => PreActivatedMediaLibrarySessionController(_libraryWithAssets()),
        ),
      ],
      child: MediaVideoRoutePage(
        relativePath: '/视频/demo.mp4',
        controllerFactory: (resource) => fake,
      ),
    );
    await tester.pump();
    await fake.waitForInitializeCount(1);
    await tester.pump();

    expect(fake.playCallCount, greaterThanOrEqualTo(1));
    expect(find.text('demo.mp4'), findsOneWidget);
  });

  testWidgets('视频 path 缺失显示恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
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

    expect(find.text('返回同步页'), findsOneWidget);

    // 本场景 media route 嵌套在 /sync 下，deep link 构建 2 层栈 → canPop
    // 为 true，点击后实际走 pop 分支退回 /sync；go 分支见下方用例。
    await tester.tap(find.text('返回同步页'));
    await settleRouteTransition(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('同步落点'), findsOneWidget);
  });

  testWidgets('恢复页按钮顶层 route 直达（单层栈）时 go 回 /sync', (tester) async {
    final prefs = await _testPrefs();
    final router = GoRouter(
      initialLocation: '/media/image',
      routes: [
        GoRoute(
          path: '/sync',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('同步落点'))),
        ),
        GoRoute(
          path: '/media/image',
          builder: (context, state) =>
              const MediaImageRoutePage(relativePath: null),
        ),
      ],
    );
    await pumpTestApp(tester, preferences: prefs, router: router);

    expect(find.text('返回同步页'), findsOneWidget);

    // media route 为顶层绝对路径，直达时仅 1 层栈 → canPop 为 false，
    // 点击后走 go 分支跳回 /sync。
    await tester.tap(find.text('返回同步页'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('同步落点'), findsOneWidget);
  });
}
