import 'package:flutter/material.dart';

import '../../../domain/models/chat_message.dart';
import '../../../../settings/domain/models/preset_prompt.dart';
import 'composer_helpers.dart';
import 'composer_send_button.dart';

class ComposerCompactActionRow extends StatelessWidget {
  const ComposerCompactActionRow({
    required this.hasModels,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.supportsReasoning,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.autoRetryEnabled,
    required this.selectedPresetPrompt,
    required this.excludedMessageCount,
    required this.onOpenSettings,
    required this.onSendPressed,
    required this.onStopStreaming,
    super.key,
  });

  final bool hasModels;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final bool supportsReasoning;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool autoRetryEnabled;
  final PresetPrompt? selectedPresetPrompt;
  final int excludedMessageCount;
  final VoidCallback onOpenSettings;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('chat-secondary-settings-button'),
            onPressed: isBusy ? null : onOpenSettings,
            icon: const Icon(Icons.tune_rounded),
            label: Text(_compactSettingsSummary()),
          ),
        ),
        const SizedBox(width: 6),
        ComposerSendButton(
          theme: Theme.of(context),
          isBusy: isBusy,
          isStreaming: isStreaming,
          isAutoRetryWaiting: isAutoRetryWaiting,
          hasModels: hasModels,
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
      supportsReasoning && reasoningEnabled
          ? effortLabel(reasoningEffort)
          : '思考关',
    );
    parts.add(autoRetryEnabled ? '重试开' : '重试关');
    parts.add(selectedPresetPrompt?.name ?? '无 Prompt');
    if (excludedMessageCount > 0) {
      parts.add('过滤 $excludedMessageCount 条');
    }
    return '更多设置 · ${parts.join(' · ')}';
  }
}
