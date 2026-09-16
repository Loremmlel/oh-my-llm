import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/preferences/chat_defaults_controller.dart';
import '../../../../application/providers/llm_model_configs_controller.dart';
import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_helpers.dart';

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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(model.displayName),
      subtitle: Text(
        '${model.modelName}${model.supportsReasoning ? ' · 支持深度思考' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '模型操作',
        onSelected: (action) async {
          if (action == 'edit') {
            onEditModelRequested(provider, model);
          } else if (await confirmSettingsDeletion(
                context,
                title: '删除模型',
                message:
                    '将从“${provider.name}”删除模型“${model.displayName}”。聊天记录会保留。',
              ) &&
              context.mounted) {
            final defaults = ref.read(chatDefaultsProvider.notifier);
            await ref
                .read(llmProviderConfigsProvider.notifier)
                .deleteModel(providerId: provider.id, modelId: model.id);
            await defaults.clearRememberedModelIdIfMatches(model.id);
            if (context.mounted) showSettingsSnackbar(context, '模型已删除');
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              '删除模型',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
