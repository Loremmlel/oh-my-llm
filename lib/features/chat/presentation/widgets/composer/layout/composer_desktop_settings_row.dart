import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/llm_usage_widgets.dart';

import '../../../../application/workspace/chat_workspace_composer_state.dart';
import '../../workspace/chat_workspace_bindings.dart';

import '../composer_helpers.dart';
import '../controls/auto_retry_toggle.dart';
import '../controls/composer_effort_pill.dart';
import '../controls/thinking_toggle.dart';

class ComposerDesktopSettingsRow extends StatelessWidget {
  const ComposerDesktopSettingsRow({
    required this.state,
    required this.bindings,
    super.key,
  });

  final ChatWorkspaceComposerReadModel state;
  final ChatWorkspaceComposerBindings bindings;

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
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    textStyle: theme.textTheme.bodySmall,
                    iconSize: 14,
                  ),
                  onPressed: bindings.onOpenFixedPromptSequenceRunner,
                  icon: const Icon(Icons.playlist_play_rounded),
                  label: const Text('固定顺序提示词'),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: state.excludedMessageCount > 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  textStyle: theme.textTheme.bodySmall,
                  iconSize: 14,
                ),
                key: const ValueKey('chat-message-filter-button'),
                // 过滤对话框只是查看/标记，不影响进行中的请求。
                onPressed: bindings.onOpenMessageFilter,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(messageFilterLabel(state.excludedMessageCount)),
              ),
              ConversationTokenUsage(summary: state.usageSummary),
            ],
          ),
        ),
      ],
    );
  }
}
