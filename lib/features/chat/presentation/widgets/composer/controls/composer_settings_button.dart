import 'package:flutter/material.dart';

import '../../../../application/workspace/chat_workspace_composer_state.dart';

import '../composer_helpers.dart';

class ComposerSettingsButton extends StatelessWidget {
  const ComposerSettingsButton({
    required this.state,
    required this.onOpenSettings,
    super.key,
  });

  final ChatWorkspaceComposerReadModel state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _compactSettingsSummary(),
      key: const ValueKey('chat-secondary-settings-button'),
      // 打开"更多设置"面板本身不影响进行中的请求。
      onPressed: onOpenSettings,
      icon: const Icon(Icons.tune_rounded),
    );
  }

  String _compactSettingsSummary() {
    final parts = <String>[];
    parts.add(
      state.supportsReasoning && state.reasoningEnabled
          ? effortLabel(state.reasoningEffort)
          : '思考关',
    );
    parts.add(state.autoRetryEnabled ? '重试开' : '重试关');
    if (state.excludedMessageCount > 0) {
      parts.add('过滤 ${state.excludedMessageCount} 条');
    }
    return '更多设置 · ${parts.join(' · ')}';
  }
}
