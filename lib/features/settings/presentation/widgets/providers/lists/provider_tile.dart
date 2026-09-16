import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../../application/preferences/chat_defaults_controller.dart';
import '../../../../application/providers/llm_model_configs_controller.dart';
import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_helpers.dart';
import 'provider_info_body.dart';
import 'provider_model_tile.dart';

class ProviderTile extends ConsumerStatefulWidget {
  const ProviderTile({
    required this.provider,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
    super.key,
  });
  final LlmProviderConfig provider;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  ConsumerState<ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends ConsumerState<ProviderTile> {
  bool _modelsExpanded = false;

  @override
  void didUpdateWidget(covariant ProviderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.models.isEmpty &&
        widget.provider.models.isNotEmpty) {
      _modelsExpanded = true;
    }
  }

  Future<void> _delete() async {
    final provider = widget.provider;
    if (!await confirmSettingsDeletion(
          context,
          title: '删除服务商',
          message:
              '将删除“${provider.name}”及其 ${provider.models.length} 个模型。聊天记录会保留。',
        ) ||
        !mounted) {
      return;
    }
    final defaults = ref.read(chatDefaultsProvider.notifier);
    await ref
        .read(llmProviderConfigsProvider.notifier)
        .deleteProviderById(provider.id);
    for (final model in provider.models) {
      await defaults.clearRememberedModelIdIfMatches(model.id);
    }
    if (mounted) showSettingsSnackbar(context, '服务商已删除');
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(provider.name, style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                key: ValueKey('add-model-${provider.id}'),
                onPressed: () => widget.onAddModelRequested(provider),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增模型'),
              ),
              PopupMenuButton<String>(
                tooltip: '服务商操作',
                onSelected: (action) {
                  if (action == 'edit') {
                    widget.onEditProviderRequested(provider);
                  }
                  if (action == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑服务商')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除服务商',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            '${provider.apiProtocol.displayName} · ${provider.models.length} 个模型',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('provider-models-toggle-${provider.id}'),
              onPressed: () =>
                  setState(() => _modelsExpanded = !_modelsExpanded),
              icon: Icon(
                _modelsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _modelsExpanded
                    ? '收起模型（${provider.models.length}）'
                    : '展开模型（${provider.models.length}）',
              ),
            ),
          ),
          if (_modelsExpanded) ...[
            ProviderInfoBody(provider: provider),
            const SizedBox(height: AppSpacing.xs),
            if (provider.models.isEmpty) const Text('还没有模型，点击“新增模型”开始配置。'),
            for (final model in provider.models)
              ProviderModelTile(
                provider: provider,
                model: model,
                onEditModelRequested: widget.onEditModelRequested,
              ),
          ],
          const Divider(),
        ],
      ),
    );
  }
}
