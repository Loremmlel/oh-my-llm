import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/shuffle_appbar_actions.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../helpers/fake_media_library.dart';
import '../helpers/fake_video_player_controller.dart';
import '../helpers/media_test_helpers.dart';

/// 记录 onPlayerExited 调用次数的随机播放控制器替身。
class RecordingShuffleController extends ShufflePlaybackController {
  RecordingShuffleController(this.initialState);

  final ShufflePlaybackState initialState;
  int onPlayerExitedCallCount = 0;

  @override
  ShufflePlaybackState build() => initialState;

  @override
  void onPlayerExited() {
    onPlayerExitedCallCount++;
  }
}

Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

/// 预激活会话的库：为第二个视频提供资源解析结果，供播放路由渲染。
FakeMediaLibrary _videoLibrary() {
  return FakeMediaLibrary()
    ..assetResults[const MediaAssetRequest(
      kind: MediaAssetKind.video,
      relativePath: '/视频/第二个.mp4',
    )] = NetworkMediaResource(
      Uri.parse('http://peer/api/media/video/视频/第二个.mp4'),
    );
}

GoRouter _shuffleRouter(RecordingShuffleController shuffleController) {
  return GoRouter(
    initialLocation: AppDestination.sync.path,
    routes: [
      GoRoute(
        path: AppDestination.sync.path,
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            actions: [ShuffleAppBarActions(currentDirectoryPath: '/视频')],
          ),
          body: const SizedBox.shrink(),
        ),
        routes: [
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
              controllerFactory: (resource) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 组装预激活会话 + 录制随机播放控制器，返回承载路由供断言导航结果。
Future<GoRouter> _pumpShuffleAppBar(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required RecordingShuffleController shuffleController,
}) async {
  final router = _shuffleRouter(shuffleController);
  await pumpTestApp(
    tester,
    preferences: prefs,
    router: router,
    extraOverrides: [
      mediaLibrarySessionProvider.overrideWith(
        () => PreActivatedMediaLibrarySessionController(_videoLibrary()),
      ),
      shufflePlaybackControllerProvider.overrideWith(() => shuffleController),
    ],
  );
  return router;
}

void main() {
  testWidgets('下一个按钮以 currentVideo.relativePath 打开 mediaVideo 路由', (
    tester,
  ) async {
    final prefs = await _testPrefs();
    final shuffleController = RecordingShuffleController(
      ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: '第一个.mp4', relativePath: '/视频/第一个.mp4'),
          VideoItem(name: '第二个.mp4', relativePath: '/视频/第二个.mp4'),
        ],
        currentIndex: 0,
        directoryPath: '/视频',
      ),
    );
    final router = await _pumpShuffleAppBar(
      tester,
      prefs: prefs,
      shuffleController: shuffleController,
    );

    await tester.tap(find.byTooltip('下一个'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync/media/video',
    );
    expect(
      router.routerDelegate.state.uri.queryParameters[AppRouteParameter
          .mediaPath],
      '/视频/第二个.mp4',
    );
    expect(find.text('第二个.mp4'), findsOneWidget);
  });

  testWidgets('pop 播放器后 onPlayerExited 恰好调用一次', (tester) async {
    final prefs = await _testPrefs();
    final shuffleController = RecordingShuffleController(
      ShufflePlaybackActive(
        playlist: const [
          VideoItem(name: '第一个.mp4', relativePath: '/视频/第一个.mp4'),
          VideoItem(name: '第二个.mp4', relativePath: '/视频/第二个.mp4'),
        ],
        currentIndex: 0,
        directoryPath: '/视频',
      ),
    );
    final router = await _pumpShuffleAppBar(
      tester,
      prefs: prefs,
      shuffleController: shuffleController,
    );

    await tester.tap(find.byTooltip('下一个'));
    await settleRouteTransition(tester);

    // 点击播放器返回按钮（IconButton(Icons.arrow_back)，无 tooltip），
    // pop 完成后应触发一次 onPlayerExited。
    await tester.tap(find.byIcon(Icons.arrow_back));
    // 播放器页面级 GestureDetector 带 onDoubleTap：tap 后手势竞技场要等
    // 双击窗口（kDoubleTapTimeout）结束才解析按钮按下，先推进窗口再等 pop 动画。
    await tester.pump(kDoubleTapTimeout);
    await settleRouteTransition(tester);

    expect(shuffleController.onPlayerExitedCallCount, 1);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });
}
