import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_destination.dart';
import '../shell/app_shell_scaffold.dart';
import '../../features/media/application/media_browser_controller.dart';
import '../../features/media/application/media_root_directory_controller.dart';
import '../../features/media/application/shuffle_playback_controller.dart';
import '../../features/media/domain/models/media_server_info.dart';
import '../../features/media/presentation/media_browser_tab.dart';
import '../../features/media/presentation/widgets/shuffle_appbar_actions.dart';
import '../../features/sync/application/sync_client_controller.dart';
import '../../features/sync/application/sync_server_controller.dart';
import '../../features/sync/application/sync_workspace_tab_preference_controller.dart';
import '../../features/sync/presentation/widgets/sync_connection_tab.dart';
import '../../features/sync/presentation/widgets/sync_operation_tab.dart';

/// Sync 与 Media 的 app 级组合页面。
///
/// 这里拥有 Tab、应用生命周期及媒体会话时机；Sync feature UI 只提供其自身子视图。
class SyncWorkspaceScreen extends ConsumerStatefulWidget {
  const SyncWorkspaceScreen({super.key});

  @override
  ConsumerState<SyncWorkspaceScreen> createState() =>
      _SyncWorkspaceScreenState();
}

class _SyncWorkspaceScreenState extends ConsumerState<SyncWorkspaceScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  bool _wasServerRunningBeforePause = false;
  late int _lastStableTabIndex;

  bool get _hasMediaTab => defaultTargetPlatform == TargetPlatform.android;
  int get _tabCount => _hasMediaTab ? 3 : 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialIndex = ref
        .read(syncWorkspaceTabPreferenceProvider)
        .clamp(0, _tabCount - 1);
    _tabController = TabController(
      initialIndex: initialIndex,
      length: _tabCount,
      vsync: this,
    );
    _lastStableTabIndex = initialIndex;
    _tabController.addListener(_onTabChanged);
    if (_hasMediaTab && initialIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initMediaSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final nextIndex = _tabController.index;
    if (_hasMediaTab && _lastStableTabIndex == 2 && nextIndex != 2) {
      ref.read(mediaBrowserControllerProvider.notifier).reset();
      ref.read(shufflePlaybackControllerProvider.notifier).reset();
    }
    if (_hasMediaTab && nextIndex == 2) _initMediaSession();
    _lastStableTabIndex = nextIndex;
    ref
        .read(syncWorkspaceTabPreferenceProvider.notifier)
        .select(nextIndex, tabCount: _tabCount);
    setState(() {});
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
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused) {
      _wasServerRunningBeforePause = ref
          .read(syncServerControllerProvider)
          .isRunning;
      ref.read(syncServerControllerProvider.notifier).stop();
      ref.read(syncClientControllerProvider.notifier).cancelAndReset();
    } else if (lifecycleState == AppLifecycleState.resumed &&
        _wasServerRunningBeforePause) {
      ref.read(syncServerControllerProvider.notifier).start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaState = _hasMediaTab && _tabController.index == 2
        ? ref.watch(mediaBrowserControllerProvider)
        : null;
    return AppShellScaffold(
      currentDestination: AppDestination.sync,
      title: '局域网同步',
      actions: mediaState?.server != null
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
            tabs: [
              const Tab(text: '连接'),
              const Tab(text: '同步'),
              if (_hasMediaTab) const Tab(text: '媒体'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SyncConnectionTab(
                  serverConfiguration: Platform.isWindows
                      ? const _MediaRootDirectoryConfiguration()
                      : null,
                ),
                const SyncOperationTab(),
                if (_hasMediaTab)
                  MediaBrowserTab(
                    onExitMediaBrowser: () => _tabController.animateTo(0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaRootDirectoryConfiguration extends ConsumerStatefulWidget {
  const _MediaRootDirectoryConfiguration();

  @override
  ConsumerState<_MediaRootDirectoryConfiguration> createState() =>
      _MediaRootDirectoryConfigurationState();
}

class _MediaRootDirectoryConfigurationState
    extends ConsumerState<_MediaRootDirectoryConfiguration> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(mediaRootDirectoryProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) return;
    _controller.text = directory;
    await ref.read(mediaRootDirectoryProvider.notifier).setDirectory(directory);
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(syncServerControllerProvider).isRunning;
    return TextField(
      controller: _controller,
      readOnly: true,
      enabled: !running,
      onTap: running ? null : _pickDirectory,
      decoration: InputDecoration(
        labelText: '媒体根目录（可选）',
        hintText: '点击选择文件夹',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: '选择文件夹',
          onPressed: running ? null : _pickDirectory,
        ),
      ),
    );
  }
}
