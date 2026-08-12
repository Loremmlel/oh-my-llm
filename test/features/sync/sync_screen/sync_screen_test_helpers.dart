import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/app/composition/sync_workspace_screen.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_import_confirm_dialog.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';

Future<AppDatabase> pumpSyncScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1200),
  List<dynamic> extraOverrides = const [],

  /// 测试在 [extraOverrides] 覆盖 [mediaLibraryFactoryProvider] 时必须
  /// 传 false，排除 composition 的生产绑定（避免重复 override）。
  bool bindMediaLibraryFactory = true,
}) async {
  return pumpTestApp(
    tester,
    child: const SyncWorkspaceScreen(),
    preferences: preferences,
    database: database,
    viewportSize: size,
    extraOverrides: extraOverrides,
    bindMediaLibraryFactory: bindMediaLibraryFactory,
  );
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
  required SettingsExportData exportData,
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
            exportData: exportData,
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
