import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/app/composition/sync_workspace_screen.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_import_confirm_dialog.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/data/udp/sync_udp_discovery.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';

Future<AppDatabase> pumpSyncScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1200),
  List<dynamic> extraOverrides = const [],

  /// 传 [router] 时改为用路由器渲染 /sync 下的 SyncWorkspaceScreen，
  /// 供系统返回会改写路由（如退回对话页）的用例断言路由变化。
  GoRouter? router,

  /// 测试在 [extraOverrides] 覆盖 [mediaLibraryFactoryProvider] 时必须
  /// 传 false，排除 composition 的生产绑定（避免重复 override）。
  bool bindMediaLibraryFactory = true,
}) async {
  return pumpTestApp(
    tester,
    child: router == null ? const SyncWorkspaceScreen() : null,
    router: router,
    preferences: preferences,
    database: database,
    viewportSize: size,
    extraOverrides: extraOverrides,
    bindMediaLibraryFactory: bindMediaLibraryFactory,
  );
}

/// 带顶层 /chat 与 /sync 路由的测试路由器：/sync 渲染 SyncWorkspaceScreen，
/// /chat 渲染占位正文，供「系统返回退回对话页」类用例验证路由变化。
GoRouter syncWorkspaceTestRouter() {
  return GoRouter(
    initialLocation: AppDestination.sync.path,
    routes: [
      GoRoute(
        path: AppDestination.chat.path,
        builder: (context, state) => const Scaffold(body: Text('对话页')),
      ),
      GoRoute(
        path: AppDestination.sync.path,
        builder: (context, state) => const SyncWorkspaceScreen(),
      ),
    ],
  );
}

/// 在测试体内切换到 Windows 平台，并在 tearDown 中复位。
///
/// 测试框架会在 body 末尾校验 foundation 调试变量已复位，而 addTearDown 在该
/// 校验之后才执行，故调用方仍需在 body 结束前显式复位（与 Android 用例一致）。
void overrideWindowsPlatform() {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

/// 固定已连接服务端，供媒体 Tab 会话测试驱动。
class SeededSyncClientController extends SyncClientController {
  SeededSyncClientController(this._seed);

  final SyncClientState _seed;

  @override
  SyncClientState build() => _seed;
}

class RecordingMediaBrowserController extends MediaBrowserController {
  static RecordingMediaBrowserController? latest;
  static MediaBrowserState? lastState;
  static int totalInitCount = 0;
  int initCount = 0;

  /// 系统返回触发 [goBack] 的次数，用于断言离屏媒体 Tab 不再被返回消费。
  int goBackCount = 0;

  @override
  MediaBrowserState build() {
    latest = this;
    return MediaBrowserState();
  }

  @override
  Future<bool> initFromActiveSession() async {
    initCount++;
    totalInitCount++;
    lastState = MediaBrowserState();
    return true;
  }

  @override
  void reset() {
    super.reset();
    lastState = MediaBrowserState();
  }

  /// 同步种子目录状态：绕过真实加载直接给定当前路径与历史，
  /// 让返回键用例独立于会话/加载时序驱动目录层级。
  void seedPathForTest({
    required String currentPath,
    required List<String> pathHistory,
  }) {
    state = state.copyWith(currentPath: currentPath, pathHistory: pathHistory);
  }

  @override
  Future<bool> goBack() async {
    goBackCount++;
    if (state.pathHistory.isEmpty) return false;
    final history = [...state.pathHistory];
    final previous = history.removeLast();
    state = state.copyWith(currentPath: previous, pathHistory: history);
    return true;
  }
}

class RecordingShufflePlaybackController extends ShufflePlaybackController {
  static RecordingShufflePlaybackController? latest;
  static ShufflePlaybackState? lastState;

  @override
  ShufflePlaybackState build() {
    latest = this;
    return super.build();
  }

  void activateForTest() {
    state = ShufflePlaybackActive(
      playlist: const [VideoItem(name: 'test.mp4', relativePath: '/test.mp4')],
      currentIndex: 0,
      directoryPath: '/',
    );
    lastState = state;
  }

  @override
  void reset() {
    super.reset();
    lastState = const ShufflePlaybackIdle();
  }
}

SyncClientState connectedSyncState() => SyncClientState(
  phase: SyncPhase.connected,
  server: const DiscoveredServer(
    deviceName: 'Test Android',
    ip: '192.168.1.5',
    httpPort: 8080,
  ),
);

Future<void> pumpImportDialog(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required SettingsSyncPreparedImport preparedImport,
  String sourceDeviceName = 'TestPC',
}) async {
  await pumpTestApp(
    tester,
    preferences: preferences,
    child: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => SyncImportConfirmDialog(
            preparedImport: preparedImport,
            sourceDeviceName: sourceDeviceName,
          ),
        ),
        child: const Text('打开对话框'),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await settleOverlayTransition(tester);
}
