import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/preferences/chat_defaults_controller.dart';
import '../../../../application/prompts/preset_prompts_controller.dart';
import '../../../../domain/models/prompts/preset_prompt.dart';
import '../../shared/settings_helpers.dart';
import 'preset_prompts_view.dart';

class PresetPromptsList extends ConsumerWidget {
  const PresetPromptsList({
    required this.templates,
    required this.onCopyToClipboardRequested,
    required this.onEditRequested,
    super.key,
  });
  final List<PresetPrompt> templates;
  final Future<void> Function(PresetPrompt template) onCopyToClipboardRequested;
  final ValueChanged<PresetPrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PresetPromptsView(
    templates: templates,
    onCopy: onCopyToClipboardRequested,
    onEdit: onEditRequested,
    onSingleSystemChanged: (template, enabled) => ref
        .read(presetPromptsProvider.notifier)
        .setSingleSystemPrompt(template.id, enabled),
    onDelete: (template) async {
      if (!await confirmSettingsDeletion(
            context,
            title: '删除预设',
            message: '将删除预设“${template.name}”。已有聊天记录会保留。',
          ) ||
          !context.mounted) {
        return;
      }
      await ref.read(presetPromptsProvider.notifier).deleteById(template.id);
      await ref
          .read(chatDefaultsProvider.notifier)
          .clearRememberedPresetPromptIdIfMatches(template.id);
      if (context.mounted) showSettingsSnackbar(context, '预设 Prompt 已删除');
    },
  );
}
