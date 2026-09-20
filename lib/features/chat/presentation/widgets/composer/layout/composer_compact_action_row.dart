import 'package:flutter/material.dart';

import '../../../../application/workspace/chat_workspace_view_state.dart';

import '../composer_helpers.dart';
import '../controls/composer_send_button.dart';

class ComposerCompactActionRow extends StatelessWidget {
  const ComposerCompactActionRow({
    required this.state,
    required this.onOpenSettings,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final ChatWorkspaceComposerReadModel state;
  final VoidCallback onOpenSettings;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: _compactSettingsSummary(),
            child: OutlinedButton.icon(
              key: const ValueKey('chat-secondary-settings-button'),
              // 打开"更多设置"面板本身不影响进行中的请求。
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('更多设置'),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ComposerSendButton(
          theme: Theme.of(context),
          isBusy: state.isBusy,
          isStreaming: state.isStreaming,
          isAutoRetryWaiting: state.isAutoRetryWaiting,
          hasModels: state.modelConfigs.isNotEmpty,
          expandLabel: true,
          onSendPressed: onSendPressed,
          onStopStreaming: onStopStreaming,
        ),
      ],
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
