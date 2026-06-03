import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/chat_defaults_controller.dart';
import '../../../application/llm_model_configs_controller.dart';
import '../../../domain/models/llm_provider_config.dart';
import '../settings_helpers.dart';
import 'provider_model_info.dart';
import 'provider_model_info_body.dart';

class ProviderModelTile extends ConsumerWidget {
  const ProviderModelTile({
    required this.provider,
    required this.model,
    required this.onEditModelRequested,
    super.key,
  });

  final LlmProviderConfig provider;
  final LlmProviderModelConfig model;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: ValueKey('edit-model-${model.id}'),
          onPressed: () => onEditModelRequested(provider, model),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑'),
        ),
        OutlinedButton.icon(
          key: ValueKey('delete-model-${model.id}'),
          onPressed: () async {
            await ref
                .read(llmProviderConfigsProvider.notifier)
                .deleteModel(providerId: provider.id, modelId: model.id);
            await ref
                .read(chatDefaultsProvider.notifier)
                .clearRememberedModelIdIfMatches(model.id);
            // ignore: use_build_context_synchronously
            showSettingsSnackbar(context, '模型已删除');
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除'),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact) ...[
                  ProviderModelInfo(model: model),
                  const SizedBox(height: 12),
                  actionButtons,
                ] else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              model.displayName,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: actionButtons,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ProviderModelInfoBody(model: model),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
