import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_destination.dart';
import '../shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/shuffle_appbar_actions.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_workspace_tab_preference_controller.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_connection_tab.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_operation_tab.dart';

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
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late int _lastStableTabIndex;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _hasMediaTab => _isAndroid || _isWindows;
  int get _tabCount => _hasMediaTab ? 3 : 2;

  @override
  void initState() {
    super.initState();
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
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final nextIndex = _tabController.index;
    if (_hasMediaTab && _lastStableTabIndex == 2 && nextIndex != 2) {
      // 离开媒体 Tab：先失效会话，再重置浏览器与随机播放
      ref.read(mediaLibrarySessionProvider.notifier).reset();
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

  /// 激活当前平台来源的媒体会话，并让浏览器从根目录加载。
  Future<void> _initMediaSession() async {
    if (!mounted || !_hasMediaTab || _tabController.index != 2) return;
    final source = _mediaSource();
    if (source == null) {
      ref
          .read(mediaLibrarySessionProvider.notifier)
          .fail(
            MediaLibraryFailure(
              MediaLibraryFailureCode.sourceUnavailable,
              _isWindows ? '尚未配置媒体根目录' : '未连接到服务端',
            ),
          );
      return;
    }
    final activated = await ref
        .read(mediaLibrarySessionProvider.notifier)
        .activate(source);
    if (!mounted || _tabController.index != 2 || !activated) return;
    await ref
        .read(mediaBrowserControllerProvider.notifier)
        .initFromActiveSession();
  }

  /// 按平台选择媒体来源：Windows 用持久化根目录直接访问本地文件系统，
  /// Android 用当前可信同步会话的 peer 地址。来源选择只发生在这里，
  /// media feature 内不做平台分支。
  MediaLibrarySource? _mediaSource() {
    if (_isWindows) {
      final root = ref.read(mediaRootDirectoryProvider)?.trim();
      if (root == null || root.isEmpty) return null;
      return LocalMediaLibrarySource(root);
    }
    if (_isAndroid) {
      final server = ref.read(syncClientControllerProvider).server;
      if (server == null) return null;
      return RemoteMediaLibrarySource(
        Uri(scheme: 'http', host: server.ip, port: server.httpPort),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isMediaTab = _hasMediaTab && _tabController.index == 2;
    final mediaSession = isMediaTab
        ? ref.watch(mediaLibrarySessionProvider)
        : null;
    final mediaBrowser = isMediaTab
        ? ref.watch(mediaBrowserControllerProvider)
        : null;
    return AppShellScaffold(
      currentDestination: AppDestination.sync,
      title: '局域网同步',
      // 随机播放按钮只在媒体 Tab 且会话 Active 时可见
      actions: mediaSession is MediaLibrarySessionActive && mediaBrowser != null
          ? [
              ShuffleAppBarActions(
                currentDirectoryPath: mediaBrowser.currentPath,
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
                  serverConfiguration: _isWindows
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
