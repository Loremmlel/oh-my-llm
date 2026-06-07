import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../media/application/media_browser_controller.dart';
import '../../media/presentation/media_browser_tab.dart';
import '../application/sync_client_controller.dart';
import '../application/sync_server_controller.dart';
import 'widgets/sync_connection_tab.dart';
import 'widgets/sync_operation_tab.dart';

const _syncLastTabIndexKey = 'sync.tab.last_index';

/// 同步页面，使用选项卡布局：Tab 1 连接管理，Tab 2 同步操作。
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  bool _wasServerRunningBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialIndex = ref
        .read(sharedPreferencesProvider)
        .getInt(_syncLastTabIndexKey) ??
        0;
    _tabController = TabController(
      initialIndex: initialIndex.clamp(0, 2),
      length: 3,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    _tabController.addListener(_onMediaTabListener);
  }

  void _onMediaTabListener() {
    if (_tabController.index == 2 && !_tabController.indexIsChanging) {
      final server = ref.read(syncClientControllerProvider).server;
      if (server != null) {
        ref
            .read(mediaBrowserControllerProvider.notifier)
            .initWithServer(server);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.removeListener(_onMediaTabListener);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      ref
          .read(sharedPreferencesProvider)
          .setInt(_syncLastTabIndexKey, _tabController.index);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasServerRunningBeforePause =
          ref.read(syncServerControllerProvider).isRunning;
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
    return AppShellScaffold(
      currentDestination: AppDestination.sync,
      title: '局域网同步',
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '连接'),
              Tab(text: '同步'),
              Tab(text: '媒体'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const SyncConnectionTab(),
                const SyncOperationTab(),
                MediaBrowserTab(
                  onExitMediaBrowser: () {
                    _tabController.animateTo(0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
