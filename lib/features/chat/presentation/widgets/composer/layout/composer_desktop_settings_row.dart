import 'package:flutter/material.dart';

import '../../../../application/workspace/chat_workspace_view_state.dart';
import '../../workspace/chat_workspace_bindings.dart';

import '../composer_helpers.dart';
import '../controls/auto_retry_toggle.dart';
import '../controls/composer_effort_pill.dart';
import '../controls/composer_send_button.dart';
import '../controls/thinking_toggle.dart';

class ComposerDesktopSettingsRow extends StatelessWidget {
  const ComposerDesktopSettingsRow({
    required this.state,
    required this.bindings,
    required this.onSendPressed,
    super.key,
  });

  final ChatWorkspaceComposerReadModel state;
  final ChatWorkspaceComposerBindings bindings;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ThinkingToggle(
                enabled: state.supportsReasoning,
                value: state.supportsReasoning && state.reasoningEnabled,
                onChanged: bindings.onReasoningEnabledChanged,
              ),
              if (state.supportsReasoning && state.reasoningEnabled)
                ComposerEffortPill(
                  theme: theme,
                  supportsReasoning: state.supportsReasoning,
                  reasoningEnabled: state.reasoningEnabled,
                  reasoningEffort: state.reasoningEffort,
                  onReasoningEffortChanged: bindings.onReasoningEffortChanged,
                ),
              AutoRetryToggle(
                enabled: true,
                value: state.autoRetryEnabled,
                onChanged: bindings.onAutoRetryEnabledChanged,
              ),
              Tooltip(
                message: '固定顺序提示词',
                child: TextButton.icon(
                  onPressed: bindings.onOpenFixedPromptSequenceRunner,
                  icon: const Icon(Icons.playlist_play_rounded),
                  label: const Text('固定顺序提示词'),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('chat-message-filter-button'),
                // 过滤对话框只是查看/标记，不影响进行中的请求。
                onPressed: bindings.onOpenMessageFilter,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(messageFilterLabel(state.excludedMessageCount)),
              ),
              Tooltip(
                message:
                    '当前会话缓存命中率：${state.cacheHitRate == null ? '暂无数据' : '${(state.cacheHitRate! * 100).toStringAsFixed(1)}%'}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.data_usage_outlined, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      state.cacheHitRate == null
                          ? '—'
                          : '${(state.cacheHitRate! * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Align(
          alignment: Alignment.topRight,
          child: ComposerSendButton(
            theme: theme,
            isBusy: state.isBusy,
            isStreaming: state.isStreaming,
            isAutoRetryWaiting: state.isAutoRetryWaiting,
            hasModels: state.modelConfigs.isNotEmpty,
            expandLabel: false,
            onSendPressed: onSendPressed,
            onStopStreaming: bindings.onStopStreaming,
          ),
        ),
      ],
    );
  }
}
