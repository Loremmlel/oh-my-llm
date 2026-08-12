import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_video_controller_factory.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../helpers/fake_media_library.dart';
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

/// 预激活会话的库：为视频资源解析提供结果，供播放路由渲染。
FakeMediaLibrary _videoLibrary(String videoPath) {
  return FakeMediaLibrary()
    ..assetResults[MediaAssetRequest(
      kind: MediaAssetKind.video,
      relativePath: videoPath,
    )] = NetworkMediaResource(
      Uri.parse('http://peer/$videoPath'),
    );
}

/// 最小 GoRouter 宿主：/sync 渲染 MediaBrowserTab，media 子路由走生产 routed pages。
///
/// [videoControllerFactory] 供断言「system Back 后播放器按生命周期释放」的
/// 用例注入并捕获 Fake 实例。
GoRouter _mediaRouter({MediaVideoControllerFactory? videoControllerFactory}) {
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
              controllerFactory:
                  videoControllerFactory ??
                  (resource) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 预激活会话 + Fake 浏览器控制器 + 测试路由的公共组装。
Future<void> _pumpMediaTab(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required FakeMediaLibrary library,
  required GoRouter router,
  required MediaBrowserState browserState,
  Map<String, List<FileItem>> itemsByPath = const {},
  Size viewportSize = const Size(1440, 1200),
}) {
  return pumpTestApp(
    tester,
    preferences: prefs,
    router: router,
    viewportSize: viewportSize,
    extraOverrides: [
      mediaLibrarySessionProvider.overrideWith(
        () => PreActivatedMediaLibrarySessionController(library),
      ),
      mediaBrowserControllerProvider.overrideWith(
        () =>
            FakeMediaBrowserController(browserState, itemsByPath: itemsByPath),
      ),
    ],
  );
}

void main() {
  testWidgets('点击图片文件名进入 media/image 子路由，back 回浏览列表', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: FakeMediaLibrary(),
      router: router,
      browserState: MediaBrowserState(
        items: [_file('/相册/猫.jpg'), _file('/相册/狗.jpg')],
      ),
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
    // 画廊以可见计数器呈现：当前目录两张图片，目标为第一张 → 1 / 2
    expect(find.text('1 / 2'), findsOneWidget);

    // viewer 的顶部按钮是 modal 关闭语义：Icons.close + tooltip「关闭图片」
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byTooltip('关闭图片'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片'));
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
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: _videoLibrary('/视频/demo.mp4'),
      router: router,
      browserState: MediaBrowserState(
        items: [_file('/视频/demo.mp4'), _file('/视频/other.mp4')],
      ),
    );

    await tester.tap(find.text('demo.mp4'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/video',
    );
    // push 后父浏览页仍在树中：列表 tile 与播放器标题各渲染一次文件名。
    expect(find.text('demo.mp4'), findsWidgets);

    // VideoTopBar 的顶部按钮是 modal 关闭语义：Icons.close + tooltip「关闭视频」
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byTooltip('关闭视频'));
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

  testWidgets('图片 viewer 第一页 system Back 关闭 viewer 回 /sync，不切页', (
    tester,
  ) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: FakeMediaLibrary(),
      router: router,
      browserState: MediaBrowserState(
        items: [_file('/相册/猫.jpg'), _file('/相册/狗.jpg')],
      ),
    );

    await tester.tap(find.text('猫.jpg'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/image',
    );
    // 确认处于第一页（1 / 2）后执行 system Back
    expect(find.text('1 / 2'), findsOneWidget);

    // 第一页从左边缘执行 system Back（Android 返回手势）由平台分发为
    // popRoute：应关闭 viewer 回 /sync，而不是把左边缘手势当成切页。
    // widget 测试只验证 route pop；手势 progress/cancel 的完整行为
    // 留给 Android smoke 覆盖。
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('狗.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('视频播放器 system Back 回 /sync 且播放器按生命周期释放一次', (tester) async {
    final prefs = await _testPrefs();
    final fake = FakeVideoPlayerController();
    final router = _mediaRouter(videoControllerFactory: (resource) => fake);
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: _videoLibrary('/视频/demo.mp4'),
      router: router,
      browserState: MediaBrowserState(
        items: [_file('/视频/demo.mp4'), _file('/视频/other.mp4')],
      ),
    );

    await tester.tap(find.text('demo.mp4'));
    await settleRouteTransition(tester);
    await fake.waitForInitializeCount(1);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/video',
    );

    // system Back 与顶部关闭按钮走同一条路由 pop：回 /sync 后页面
    // dispose，播放器按既有生命周期只释放一次。
    await tester.binding.handlePopRoute();
    await settleRouteTransition(tester);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('other.mp4'), findsOneWidget);
    expect(fake.disposeCount, 1);
  });

  testWidgets('点击目录只改变浏览路径，不产生媒体子路由', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: FakeMediaLibrary(),
      router: router,
      browserState: MediaBrowserState(items: [_dir('/相册'), _file('/相册/猫.jpg')]),
      itemsByPath: {
        '/相册': [_file('/相册/猫.jpg'), _file('/相册/狗.jpg')],
      },
    );

    await tester.tap(find.text('相册'));
    // fake navigateTo 同步切换目录内容，单帧即可呈现
    await tester.pump();

    // 目录点击不 push 子路由：路径栏与内容区同步更新到 /相册
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('狗.jpg'), findsOneWidget);
  });

  testWidgets('会话不可用时显示媒体会话不可用占位，不渲染文件列表', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    await pumpTestApp(tester, preferences: prefs, router: router);

    // 未激活会话 → 占位页而非浏览网格
    expect(find.text('媒体会话不可用'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });

  // 紧凑竖屏 / 受限横屏 / 宽屏三类布局
  const mediaSmokeViewports = [Size(390, 844), Size(844, 390), Size(1024, 768)];

  for (final viewportSize in mediaSmokeViewports) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 路径栏与目录/图片/视频可达',
      (tester) async {
        final prefs = await _testPrefs();
        final router = _mediaRouter();
        await _pumpMediaTab(
          tester,
          prefs: prefs,
          library: FakeMediaLibrary(),
          router: router,
          viewportSize: viewportSize,
          browserState: MediaBrowserState(
            items: [_dir('/相册'), _file('/相册/猫.jpg'), _file('/视频/demo.mp4')],
          ),
        );

        expect(find.text('🏠'), findsOneWidget);
        expect(find.text('相册'), findsOneWidget);
        expect(find.text('猫.jpg'), findsOneWidget);
        expect(find.text('demo.mp4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('缩略图解析失败只回退该 tile 图标，网格其余项与整体渲染不受影响', (tester) async {
    final prefs = await _testPrefs();
    final router = _mediaRouter();
    final library = FakeMediaLibrary()
      ..thumbnailFailure = const MediaLibraryFailure(
        MediaLibraryFailureCode.thumbnailUnavailable,
        '缩略图不可用',
      );
    await _pumpMediaTab(
      tester,
      prefs: prefs,
      library: library,
      router: router,
      browserState: MediaBrowserState(
        items: [
          // 带缩略图信号、解析必定失败的图片：验证单 tile 回退
          FileItem(
            name: '猫.jpg',
            isDirectory: false,
            sizeBytes: 1,
            relativePath: '/相册/猫.jpg',
            hasThumbnail: true,
          ),
          // 目录 tile 不参与缩略图解析
          _dir('/相册'),
          // 无缩略图信号的文件直接走回退图标
          _file('/文档/笔记.txt'),
        ],
      ),
    );

    // 失败 item 的 tile 回退到图片图标
    expect(find.byIcon(Icons.image), findsOneWidget);
    // 其余 tile 正常渲染：目录图标、普通文件图标与文件名均可见
    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    expect(find.text('猫.jpg'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('笔记.txt'), findsOneWidget);
    // 缩略图失败不升格为 grid 级错误：错误态图标不出现
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
