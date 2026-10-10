import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

class ComposerProviderModelRow extends StatelessWidget {
  const ComposerProviderModelRow({
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.onProviderSelected,
    required this.onModelSelected,
    this.templateField,
    super.key,
  });

  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final Widget? templateField;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Semantics(
            label: '服务商',
            child: AppDropdownField<String>(
              key: const ValueKey('chat-provider-selector'),
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              initialValue: selectedProviderId,
              decoration: InputDecoration(
                isDense: true,
                hintText: hasModels ? '选择服务商' : '请先在设置页新增服务商与模型',
              ),
              items: modelProviders
                  .map((provider) {
                    return DropdownMenuItem<String>(
                      value: provider.id,
                      child: Text(
                        provider.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  })
                  .toList(growable: false),
              // 流式期间切换服务商/模型只影响下次发送，进行中的请求使用发送时快照。
              onChanged: modelProviders.isEmpty
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      onProviderSelected(value);
                    },
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Semantics(
            label: '模型',
            child: AppDropdownField<String>(
              key: const ValueKey('chat-model-selector'),
              initialValue: selectedModel?.id,
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              decoration: InputDecoration(
                isDense: true,
                hintText: !hasModels
                    ? '请先在设置页新增服务商与模型'
                    : selectedProviderId == null
                    ? '请先选择服务商'
                    : modelConfigs.isEmpty
                    ? '当前服务商还没有模型'
                    : '选择模型',
              ),
              items: modelConfigs
                  .map((config) {
                    return DropdownMenuItem<String>(
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
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      onModelSelected(value);
                    },
            ),
          ),
        ),
        if (templateField != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: templateField!),
        ],
      ],
    );
  }
}
