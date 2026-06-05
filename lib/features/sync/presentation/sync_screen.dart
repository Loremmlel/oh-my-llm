import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell_scaffold.dart';
import '../../../app/navigation/app_destination.dart';
import '../application/sync_client_controller.dart';
import '../application/sync_server_controller.dart';
import 'widgets/sync_client_panel.dart';
import 'widgets/sync_server_panel.dart';

/// 同步页面，支持服务端广播和客户端同步两种模式。
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen>
    with WidgetsBindingObserver {
  bool _isServerMode = false;
  bool _wasRunningBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasRunningBeforePause =
          ref.read(syncServerControllerProvider).isRunning;
      _cleanupResources();
    } else if (state == AppLifecycleState.resumed) {
      if (_isServerMode && _wasRunningBeforePause) {
        ref.read(syncServerControllerProvider.notifier).start();
      }
    }
  }

  void _cleanupResources() {
    ref.read(syncServerControllerProvider.notifier).stop();
    ref.read(syncClientControllerProvider.notifier).cancelAndReset();
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      currentDestination: AppDestination.sync,
      title: '局域网同步',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildModeSelector(context),
          const SizedBox(height: 16),
          if (_isServerMode)
            const SyncServerPanel()
          else
            const SyncClientPanel(),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('作为客户端'), icon: Icon(Icons.download_rounded)),
        ButtonSegment(value: true, label: Text('作为服务端'), icon: Icon(Icons.upload_rounded)),
      ],
      selected: {_isServerMode},
      onSelectionChanged: (selected) {
        _cleanupResources();
        setState(() => _isServerMode = selected.first);
      },
    );
  }
}
