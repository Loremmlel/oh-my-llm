import 'package:flutter/material.dart';

import '../../../domain/models/chat_message.dart';
import '../auto_retry_toggle.dart';
import '../thinking_toggle.dart';
import 'composer_effort_pill.dart';
import 'composer_helpers.dart';
import 'composer_send_button.dart';

class ComposerDesktopSettingsRow extends StatelessWidget {
  const ComposerDesktopSettingsRow({
    required this.theme,
    required this.hasModels,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.onReasoningEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    required this.excludedMessageCount,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final ThemeData theme;
  final bool hasModels;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final int excludedMessageCount;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
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
                enabled: supportsReasoning,
                value: supportsReasoning && reasoningEnabled,
                onChanged: onReasoningEnabledChanged,
              ),
              if (supportsReasoning && reasoningEnabled)
                ComposerEffortPill(
                  theme: theme,
                  supportsReasoning: supportsReasoning,
                  reasoningEnabled: reasoningEnabled,
                  reasoningEffort: reasoningEffort,
                  onReasoningEffortChanged: onReasoningEffortChanged,
                ),
              AutoRetryToggle(
                enabled: true,
                value: autoRetryEnabled,
                onChanged: onAutoRetryEnabledChanged,
              ),
              Tooltip(
                message: '固定顺序提示词',
                child: OutlinedButton.icon(
                  onPressed: onOpenFixedPromptSequenceRunner,
                  icon: const Icon(Icons.playlist_play_rounded),
                  label: const Text('固定顺序提示词'),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('chat-message-filter-button'),
                onPressed: isBusy ? null : onOpenMessageFilter,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(messageFilterLabel(excludedMessageCount)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Align(
          alignment: Alignment.topRight,
          child: ComposerSendButton(
            theme: theme,
            isBusy: isBusy,
            isStreaming: isStreaming,
            isAutoRetryWaiting: isAutoRetryWaiting,
            hasModels: hasModels,
            expandLabel: false,
            onSendPressed: onSendPressed,
            onStopStreaming: onStopStreaming,
          ),
        ),
      ],
    );
  }
}
