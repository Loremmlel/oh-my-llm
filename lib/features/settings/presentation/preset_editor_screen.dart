import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../application/prompts/fixed_prompt_sequences_controller.dart';
import '../application/prompts/memory_prompts_controller.dart';
import '../application/prompts/preset_prompts_controller.dart';
import '../application/prompts/template_prompts_controller.dart';
import '../domain/models/prompts/fixed_prompt_sequence.dart';
import '../domain/models/prompts/memory_prompt.dart';
import '../domain/models/prompts/preset_prompt.dart';
import '../domain/models/prompts/template_prompt.dart';
import 'widgets/prompts/forms/fixed_prompt_sequence_editor.dart';
import 'widgets/prompts/forms/memory_prompt_editor.dart';
import 'widgets/prompts/forms/preset_prompt_editor.dart';
import 'widgets/prompts/forms/template_prompt_editor.dart';

Widget _buildEntityEditorRoute<T>({
  required T? entity,
  required String? entityId,
  required String targetName,
  required String listName,
  required Widget Function(T? initialValue) builder,
}) {
  if (entityId != null && entity == null) {
    return Scaffold(
      appBar: AppBar(title: Text('$targetName不存在')),
      body: Center(child: Text('该$targetName可能已被删除，请返回$listName列表。')),
    );
  }
  return builder(entity);
}

/// 编辑路由只携带 ID，预设和保存继续由设置领域拥有。
class PresetEditorScreen extends ConsumerWidget {
  const PresetEditorScreen({this.presetId, super.key});
  final String? presetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _buildEntityEditorRoute(
    entity: ref
        .watch(presetPromptsProvider)
        .where((p) => p.id == presetId)
        .firstOrNull,
    entityId: presetId,
    targetName: '预设',
    listName: '预设',
    builder: (preset) => PresetPromptEditor(
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
              randomHeader: preset?.randomHeader ?? false,
              customReasoningTag: data.customReasoningTag,
              updatedAt: DateTime.now(),
            ),
          ),
    ),
  );
}

/// 记忆总结提示词编辑路由页面。
class MemoryPromptEditorScreen extends ConsumerWidget {
  const MemoryPromptEditorScreen({this.promptId, super.key});
  final String? promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _buildEntityEditorRoute(
    entity: ref
        .watch(memoryPromptsProvider)
        .where((p) => p.id == promptId)
        .firstOrNull,
    entityId: promptId,
    targetName: '记忆总结提示词',
    listName: '提示词',
    builder: (prompt) => MemoryPromptEditor(
      initialValue: prompt,
      onSubmit: (data) => ref
          .read(memoryPromptsProvider.notifier)
          .upsert(
            MemoryPrompt(
              id: prompt?.id ?? generateEntityId(),
              name: data.name,
              content: data.content,
              updatedAt: DateTime.now(),
            ),
          ),
    ),
  );
}

/// 模板提示词编辑路由页面。
class TemplatePromptEditorScreen extends ConsumerWidget {
  const TemplatePromptEditorScreen({this.promptId, super.key});
  final String? promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _buildEntityEditorRoute(
    entity: ref
        .watch(templatePromptsProvider)
        .where((p) => p.id == promptId)
        .firstOrNull,
    entityId: promptId,
    targetName: '模板提示词',
    listName: '提示词',
    builder: (prompt) => TemplatePromptEditor(
      initialValue: prompt,
      onSubmit: (data) => ref
          .read(templatePromptsProvider.notifier)
          .upsert(
            TemplatePrompt(
              id: prompt?.id ?? generateEntityId(),
              title: data.title,
              content: data.content,
              variables: data.variables,
              updatedAt: DateTime.now(),
            ),
          ),
    ),
  );
}

/// 固定顺序提示词编辑路由页面。
class FixedPromptSequenceEditorScreen extends ConsumerWidget {
  const FixedPromptSequenceEditorScreen({this.sequenceId, super.key});
  final String? sequenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _buildEntityEditorRoute(
    entity: ref
        .watch(fixedPromptSequencesProvider)
        .where((s) => s.id == sequenceId)
        .firstOrNull,
    entityId: sequenceId,
    targetName: '固定顺序提示词',
    listName: '提示词',
    builder: (sequence) => FixedPromptSequenceEditor(
      initialValue: sequence,
      onSubmit: (data) => ref
          .read(fixedPromptSequencesProvider.notifier)
          .upsert(
            FixedPromptSequence(
              id: sequence?.id ?? generateEntityId(),
              name: data.name,
              steps: data.steps,
              updatedAt: DateTime.now(),
            ),
          ),
    ),
  );
}
