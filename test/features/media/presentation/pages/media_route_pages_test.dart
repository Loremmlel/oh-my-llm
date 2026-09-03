import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import '../../../../helpers/test_harness.dart';
import '../../helpers/fake_media_library.dart';
import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';
import '../../helpers/media_test_helpers.dart';

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

VideoPlayerPlatformBindings _mobileTestBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

FileItem _image(String path) => FileItem(
  name: path.split('/').last,
  isDirectory: false,
  sizeBytes: 1,
  relativePath: path,
);

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
      kind: MediaAssetKind.video,
      relativePath: '/视频/demo.mp4',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/video/视频/demo.mp4'),
    );
}

GoRouter _recoveryRouter(Widget page) {
  return GoRouter(
    initialLocation: '/media',
    routes: [GoRoute(path: '/media', builder: (context, state) => page)],
  );
}

void main() {
  testWidgets('合法图片 target 恢复当前目录画廊位置', (tester) async {
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

    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('缺失图片 path 显示链接无效恢复页', (tester) async {
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: _recoveryRouter(const MediaImageRoutePage(relativePath: null)),
    );

    expect(find.text('媒体链接无效'), findsOneWidget);
  });

  testWidgets('未激活会话显示会话失效恢复页', (tester) async {
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

  testWidgets('合法视频解析资源并初始化播放器', (tester) async {
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
        bindingsFactory: _mobileTestBindings,
        controllerFactory: (resource) => fake,
      ),
    );
    await tester.pump();
    await fake.waitForInitializeCount(1);
    await tester.pump();

    expect(fake.playCallCount, greaterThanOrEqualTo(1));
    expect(find.text('demo.mp4'), findsOneWidget);
  });

  testWidgets('重复进入视频路由创建独立平台会话', (tester) async {
    final fake = FakeVideoPlayerController();
    final created = <VideoPlayerPlatformBindings>[];
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaLibrarySessionProvider.overrideWith(
          () => PreActivatedMediaLibrarySessionController(_libraryWithAssets()),
        ),
      ],
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => MediaVideoRoutePage(
                relativePath: '/视频/demo.mp4',
                bindingsFactory: () {
                  final bindings = _mobileTestBindings();
                  created.add(bindings);
                  return bindings;
                },
                controllerFactory: (resource) => fake,
              ),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          ),
          child: const Text('打开视频'),
        ),
      ),
    );

    await tester.tap(find.text('打开视频'));
    await tester.pump();
    await tester.pump();
    expect(created, hasLength(1));

    await tester.tap(find.byTooltip('关闭视频'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('打开视频'));
    await tester.pump();
    await tester.pump();

    expect(fake.initializeCallCount, 2);
    expect(created, hasLength(2));
    expect(identical(created[0], created[1]), isFalse);
  });

  testWidgets('视频资源解析失败不创建平台会话', (tester) async {
    var factoryCalls = 0;
    final prefs = await _testPrefs();
    await pumpTestApp(
      tester,
      preferences: prefs,
      extraOverrides: [
        mediaLibrarySessionProvider.overrideWith(
          () => PreActivatedMediaLibrarySessionController(_libraryWithAssets()),
        ),
      ],
      router: _recoveryRouter(
        MediaVideoRoutePage(
          relativePath: '/视频/不存在.mp4',
          bindingsFactory: () {
            factoryCalls++;
            return _mobileTestBindings();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('媒体资源不可用'), findsOneWidget);
    expect(factoryCalls, 0);
  });

  testWidgets('嵌套路由恢复按钮 pop 回同步页', (tester) async {
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

    await tester.tap(find.text('返回同步页'));
    await settleRouteTransition(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/sync');
    expect(find.text('同步落点'), findsOneWidget);
  });

  testWidgets('顶层恢复按钮 go 回同步页', (tester) async {
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

    await tester.tap(find.text('返回同步页'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });
}
