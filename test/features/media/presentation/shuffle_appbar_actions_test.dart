import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/shuffle_appbar_actions.dart';

import '../../../helpers/test_harness.dart';
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
              controllerFactory: (uri) => FakeVideoPlayerController(),
            ),
          ),
        ],
      ),
    ],
  );
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
    final router = _shuffleRouter(shuffleController);
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        shufflePlaybackControllerProvider.overrideWith(() => shuffleController),
        mediaBrowserControllerProvider.overrideWith(
          () =>
              FakeMediaBrowserController(MediaBrowserState(server: testServer)),
        ),
      ],
    );

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

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
    final router = _shuffleRouter(shuffleController);
    await pumpTestApp(
      tester,
      preferences: prefs,
      router: router,
      extraOverrides: [
        shufflePlaybackControllerProvider.overrideWith(() => shuffleController),
        mediaBrowserControllerProvider.overrideWith(
          () =>
              FakeMediaBrowserController(MediaBrowserState(server: testServer)),
        ),
      ],
    );

    await tester.tap(find.byTooltip('下一个'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 点击播放器返回按钮（IconButton(Icons.arrow_back)，无 tooltip），
    // pop 完成后应触发一次 onPlayerExited。
    await tester.tap(find.byIcon(Icons.arrow_back));
    // 播放器页面级 GestureDetector 带 onDoubleTap：tap 后手势竞技场 hold
    // 300ms 双点窗口才解析按钮按下，须先推进时间再等 pop 动画。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(shuffleController.onPlayerExitedCallCount, 1);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/sync',
    );
  });
}
