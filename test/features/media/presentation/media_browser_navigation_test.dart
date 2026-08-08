import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
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

/// 最小 GoRouter 宿主：/sync 渲染 MediaBrowserTab，media 子路由走生产 routed pages。
GoRouter _mediaRouter() {
  return GoRouter(
    initialLocation: AppDestination.sync.path,
    routes: [
      GoRoute(
        path: AppDestination.sync.path,
        builder: (context, state) =>
            Scaffold(body: MediaBrowserTab(onExitMediaBrowser: () {})),
        routes: [
          GoRoute(
            path: 'media/image',
            name: AppRouteName.mediaImage,
            builder: (context, state) => MediaImageRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
              controllerFactory: (uri) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('点击图片文件名进入 media/image 子路由，back 回浏览列表', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_file('/相册/猫.jpg'), _file('/相册/狗.jpg')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('猫.jpg'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/image',
    );
    expect(
      router.routerDelegate.state.uri.queryParameters[AppRouteParameter
          .mediaPath],
      '/相册/猫.jpg',
    );
    expect(find.byType(MediaImageRoutePage), findsOneWidget);

    // viewer 的返回按钮是 IconButton(Icons.arrow_back)，无 tooltip。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('狗.jpg'), findsOneWidget);
  });

  testWidgets('点击视频文件名进入 media/video 子路由，back 回浏览页', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_file('/视频/demo.mp4'), _file('/视频/other.mp4')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('demo.mp4'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/video',
    );
    // push 后父浏览页仍在树中：列表 tile 与播放器标题各渲染一次文件名。
    expect(find.text('demo.mp4'), findsWidgets);

    // VideoTopBar 的返回按钮也是 IconButton(Icons.arrow_back)，无 tooltip。
    await tester.tap(find.byIcon(Icons.arrow_back));
    // 播放器页面级 GestureDetector 带 onDoubleTap：tap 后手势竞技场要等
    // 双击窗口（kDoubleTapTimeout）结束才解析按钮按下，先推进窗口再等 pop 动画。
    await tester.pump(kDoubleTapTimeout);
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('other.mp4'), findsOneWidget);
  });

  testWidgets('点击目录只改变浏览路径，不产生媒体子路由', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(
              server: testServer,
              items: [_dir('/相册'), _file('/相册/猫.jpg')],
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('相册'));
    // 目录切换同步进入加载态；测试中真实 HTTP 请求不保证返回，精确推进
    // 到请求超时契约（10 秒）让加载落定，避免残留计时器泄漏到用例结束。
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    // 目录点击不 push 子路由
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });

  testWidgets('server 缺失时点击媒体文件不导航', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        mediaBrowserControllerProvider.overrideWith(
          () => FakeMediaBrowserController(
            MediaBrowserState(items: [_file('/相册/猫.jpg')]),
          ),
        ),
      ],
    );

    await tester.tap(find.text('猫.jpg'));
    // server 缺失时点击是空操作，无状态变更与动画，单帧即可
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.byType(MediaImageRoutePage), findsNothing);
  });

  const mediaSmokeViewports = [
    Size(390, 844),
    Size(600, 900),
    Size(844, 390),
    Size(1024, 768),
    Size(1440, 900),
  ];

  for (final viewportSize in mediaSmokeViewports) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 路径栏与目录/图片/视频可达',
      (tester) async {
        final prefs = await _testPrefs();
        final router = _mediaRouter();
        await pumpTestApp(
          tester,
          preferences: prefs,
          router: router,
          viewportSize: viewportSize,
          extraOverrides: [
            mediaBrowserControllerProvider.overrideWith(
              () => FakeMediaBrowserController(
                MediaBrowserState(
                  server: testServer,
                  items: [
                    _dir('/相册'),
                    _file('/相册/猫.jpg'),
                    _file('/视频/demo.mp4'),
                  ],
                ),
              ),
            ),
          ],
        );

        expect(find.text('🏠'), findsOneWidget);
        expect(find.text('相册'), findsOneWidget);
        expect(find.text('猫.jpg'), findsOneWidget);
        expect(find.text('demo.mp4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final viewportSize in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 图片 route push/back 保持 URI 契约',
      (tester) async {
        final prefs = await _testPrefs();
        final router = _mediaRouter();
        await pumpTestApp(
          tester,
          preferences: prefs,
          router: router,
          viewportSize: viewportSize,
          extraOverrides: [
            mediaBrowserControllerProvider.overrideWith(
              () => FakeMediaBrowserController(
                MediaBrowserState(
                  server: testServer,
                  items: [_file('/相册/猫.jpg')],
                ),
              ),
            ),
          ],
        );

        await tester.tap(find.text('猫.jpg'));
        await settleRouteTransition(tester);
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .matches
              .last
              .matchedLocation,
          '/sync/media/image',
        );

        await tester.tap(find.byIcon(Icons.arrow_back));
        await settleRouteTransition(tester);
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .matches
              .last
              .matchedLocation,
          '/sync',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
