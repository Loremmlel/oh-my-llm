import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../domain/models/llm_model_config.dart';
import '../../domain/models/prompt_template.dart';

const String noPromptTemplateValue = '__no_prompt_template__';

/// 聊天默认项设置区，用于选择默认模型和默认 Prompt。
class ChatDefaultsSection extends ConsumerWidget {
  const ChatDefaultsSection({
    required this.modelConfigs,
    required this.promptTemplates,
    required this.defaultModelId,
    required this.defaultPromptTemplateId,
    super.key,
  });

  final List<LlmModelConfig> modelConfigs;
  final List<PromptTemplate> promptTemplates;
  final String? defaultModelId;
  final String? defaultPromptTemplateId;

  @override
  /// 构建默认模型和默认 Prompt 的两个下拉选择器。
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedModelId =
        modelConfigs.any((config) {
          return config.id == defaultModelId;
        })
        ? defaultModelId
        : modelConfigs.firstOrNull?.id;
    final resolvedPromptValue =
        promptTemplates.any((template) {
          return template.id == defaultPromptTemplateId;
        })
        ? defaultPromptTemplateId
        : noPromptTemplateValue;

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
                      .setDefaultModelId(value);
                },
          decoration: const InputDecoration(
            labelText: '默认模型',
            helperText: '会用于新建对话或未指定模型的对话。',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(resolvedPromptValue),
          initialValue: resolvedPromptValue,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: noPromptTemplateValue,
              child: Text('不使用'),
            ),
            ...promptTemplates.map((template) {
              return DropdownMenuItem(
                value: template.id,
                child: Text(template.name, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: (value) async {
            await ref
                .read(chatDefaultsProvider.notifier)
                .setDefaultPromptTemplateId(
                  value == noPromptTemplateValue ? null : value,
                );
          },
          decoration: const InputDecoration(
            labelText: '默认 Prompt',
            helperText: '会在聊天发送时自动插入到历史最前面。',
          ),
        ),
      ],
    );
  }
}
