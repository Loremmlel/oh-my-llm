import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../application/prompts/preset_prompts_controller.dart';
import '../domain/models/prompts/preset_prompt.dart';
import 'widgets/prompts/forms/preset_prompt_editor.dart';

/// 编辑路由只携带 ID，预设和保存继续由设置领域拥有。
class PresetEditorScreen extends ConsumerWidget {
  const PresetEditorScreen({this.presetId, super.key});
  final String? presetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref
        .watch(presetPromptsProvider)
        .where((p) => p.id == presetId)
        .firstOrNull;
    if (presetId != null && preset == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('预设不存在')),
        body: const Center(child: Text('该预设可能已被删除，请返回预设列表。')),
      );
    }
    return PresetPromptEditor(
      initialValue: preset,
      onSubmit: (data) => ref
          .read(presetPromptsProvider.notifier)
          .upsert(
            PresetPrompt(
              id: preset?.id ?? generateEntityId(),
              name: data.name,
              messages: data.messages,
              syntax: data.syntax,
              singleSystemPrompt: preset?.singleSystemPrompt ?? false,
              customReasoningTag: data.customReasoningTag,
              updatedAt: DateTime.now(),
            ),
          ),
    );
  }
}
