import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/chat_defaults_controller.dart';
import '../../../domain/models/llm_model_config.dart';
import '../../../domain/models/preset_prompt.dart';

const String noPresetPromptValue = '__no_preset_prompt__';

/// 聊天页最近一次选择记忆设置区。
class ChatDefaultsSection extends ConsumerWidget {
  const ChatDefaultsSection({
    required this.modelConfigs,
    required this.presetPrompts,
    required this.defaultModelId,
    required this.defaultPresetPromptId,
    super.key,
  });

  final List<LlmModelConfig> modelConfigs;
  final List<PresetPrompt> presetPrompts;
  final String? defaultModelId;
  final String? defaultPresetPromptId;

  @override
  /// 构建最近一次模型和预设 Prompt 记忆的两个下拉选择器。
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedModelId =
        modelConfigs.any((config) {
          return config.id == defaultModelId;
        })
        ? defaultModelId
        : modelConfigs.firstOrNull?.id;
    final resolvedPromptValue =
        presetPrompts.any((template) {
          return template.id == defaultPresetPromptId;
        })
        ? defaultPresetPromptId
        : noPresetPromptValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(resolvedModelId),
          initialValue: resolvedModelId,
          isExpanded: true,
          items: modelConfigs
              .map((config) {
                return DropdownMenuItem(
                  value: config.id,
                  child: Text(
                    config.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              })
              .toList(growable: false),
          onChanged: modelConfigs.isEmpty
              ? null
              : (value) async {
                  await ref
                      .read(chatDefaultsProvider.notifier)
                      .rememberModelId(value);
                },
          decoration: const InputDecoration(
            labelText: '默认模型',
            helperText: '会作为聊天页最近一次模型选择记忆。',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(resolvedPromptValue),
          initialValue: resolvedPromptValue,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: noPresetPromptValue,
              child: Text('不使用'),
            ),
            ...presetPrompts.map((template) {
              return DropdownMenuItem(
                value: template.id,
                child: Text(template.name, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: (value) async {
            await ref
                .read(chatDefaultsProvider.notifier)
                .rememberPresetPromptId(
                  value == noPresetPromptValue ? null : value,
                );
          },
          decoration: const InputDecoration(
            labelText: '预设 Prompt 记忆',
            helperText: '会作为聊天页最近一次预设 Prompt 选择记忆。',
          ),
        ),
      ],
    );
  }
}
