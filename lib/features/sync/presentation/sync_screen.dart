import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../media/application/media_browser_controller.dart';
import '../../media/application/shuffle_playback_controller.dart';
import '../../media/domain/models/media_server_info.dart';
import '../../media/presentation/media_browser_tab.dart';
import '../../media/presentation/widgets/shuffle_appbar_actions.dart';
import '../application/sync_client_controller.dart';
import '../application/sync_server_controller.dart';
import 'widgets/sync_connection_tab.dart';
import 'widgets/sync_operation_tab.dart';

const _syncLastTabIndexKey = 'sync.tab.last_index';

/// 同步页面，使用选项卡布局。
///
/// Android：连接 / 同步 / 媒体（3 Tab）
/// 其他平台：连接 / 同步（2 Tab，无媒体浏览器）
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  bool _wasServerRunningBeforePause = false;
  late int _lastStableTabIndex;

  /// 媒体浏览器仅 Android 客户端启用。
  bool get _hasMediaTab => defaultTargetPlatform == TargetPlatform.android;

  int get _tabCount => _hasMediaTab ? 3 : 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialIndex =
        ref.read(sharedPreferencesProvider).getInt(_syncLastTabIndexKey) ?? 0;
    _tabController = TabController(
      initialIndex: initialIndex.clamp(0, _tabCount - 1),
      length: _tabCount,
      vsync: this,
    );
    _lastStableTabIndex = _tabController.index;
    _tabController.addListener(_onTabChanged);
    if (_hasMediaTab && _lastStableTabIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initMediaSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final nextIndex = _tabController.index;
      if (_hasMediaTab && _lastStableTabIndex == 2 && nextIndex != 2) {
        ref.read(mediaBrowserControllerProvider.notifier).reset();
        ref.read(shufflePlaybackControllerProvider.notifier).reset();
      }
      if (_hasMediaTab && nextIndex == 2) _initMediaSession();
      _lastStableTabIndex = nextIndex;
      ref
          .read(sharedPreferencesProvider)
          .setInt(_syncLastTabIndexKey, nextIndex);
      setState(() {}); // 触发 rebuild 以更新 AppBar actions 可见性
    }
  }

  void _initMediaSession() {
    if (!mounted || !_hasMediaTab || _tabController.index != 2) return;
    final server = ref.read(syncClientControllerProvider).server;
    if (server == null) return;
    ref
        .read(mediaBrowserControllerProvider.notifier)
        .initWithServer(
          MediaServerInfo(ip: server.ip, httpPort: server.httpPort),
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasServerRunningBeforePause = ref
          .read(syncServerControllerProvider)
          .isRunning;
      ref.read(syncServerControllerProvider.notifier).stop();
      ref.read(syncClientControllerProvider.notifier).cancelAndReset();
    } else if (state == AppLifecycleState.resumed) {
      if (_wasServerRunningBeforePause) {
        ref.read(syncServerControllerProvider.notifier).start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const Tab(text: '连接'),
      const Tab(text: '同步'),
      if (_hasMediaTab) const Tab(text: '媒体'),
    ];

    final tabViews = <Widget>[
      const SyncConnectionTab(),
      const SyncOperationTab(),
      if (_hasMediaTab)
        MediaBrowserTab(
          onExitMediaBrowser: () {
            _tabController.animateTo(0);
          },
        ),
    ];

    // 仅在媒体 Tab 选中且有连接 server 时显示随机播放按钮
    final mediaState = _hasMediaTab && _tabController.index == 2
        ? ref.watch(mediaBrowserControllerProvider)
        : null;
    final showShuffleActions = mediaState?.server != null;

    return AppShellScaffold(
      currentDestination: AppDestination.sync,
      title: '局域网同步',
      actions: showShuffleActions
          ? [
              ShuffleAppBarActions(
                currentDirectoryPath: mediaState!.currentPath,
              ),
            ]
          : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(controller: _tabController, children: tabViews),
          ),
        ],
      ),
    );
  }
}
