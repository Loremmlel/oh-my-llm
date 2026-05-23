import 'package:flutter/material.dart';

import '../../../../settings/domain/models/llm_model_config.dart';
import '../../../../settings/domain/models/llm_provider_config.dart';

class ComposerProviderModelRow extends StatelessWidget {
  const ComposerProviderModelRow({
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.isBusy,
    required this.onProviderSelected,
    required this.onModelSelected,
    super.key,
  });

  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final bool isBusy;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-provider-selector'),
            isExpanded: true,
            initialValue: selectedProviderId,
            decoration: InputDecoration(
              labelText: '服务商',
              hintText: hasModels ? null : '请先在设置页新增服务商与模型',
            ),
            items: modelProviders
                .map((provider) {
                  return DropdownMenuItem<String>(
                    value: provider.id,
                    child: Text(provider.name, overflow: TextOverflow.ellipsis),
                  );
                })
                .toList(growable: false),
            onChanged: isBusy || modelProviders.isEmpty
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onProviderSelected(value);
                  },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('chat-model-selector'),
            initialValue: selectedModel?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '模型',
              hintText: !hasModels
                  ? '请先在设置页新增服务商与模型'
                  : selectedProviderId == null
                  ? '请先选择服务商'
                  : modelConfigs.isEmpty
                  ? '当前服务商还没有模型'
                  : null,
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
            onChanged: isBusy || modelConfigs.isEmpty
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    onModelSelected(value);
                  },
          ),
        ),
      ],
    );
  }
}
