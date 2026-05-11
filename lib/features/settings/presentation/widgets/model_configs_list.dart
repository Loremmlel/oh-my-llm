import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../application/llm_model_configs_controller.dart';
import '../../domain/models/llm_provider_config.dart';
import 'settings_empty_state.dart';

/// 服务商配置列表，负责展示服务商信息和其下模型。
class ModelConfigsList extends ConsumerWidget {
  const ModelConfigsList({
    required this.providers,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
    super.key,
  });

  final List<LlmProviderConfig> providers;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (providers.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.hub_outlined,
        title: '还没有服务商配置',
        description: '先添加一个服务商，再在服务商下添加模型，聊天页才能真正发起对话请求。',
      );
    }

    return Column(
      children: [
        for (final provider in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProviderTile(
              provider: provider,
              onEditProviderRequested: onEditProviderRequested,
              onAddModelRequested: onAddModelRequested,
              onEditModelRequested: onEditModelRequested,
            ),
          ),
      ],
    );
  }
}

class _ProviderTile extends ConsumerStatefulWidget {
  const _ProviderTile({
    required this.provider,
    required this.onEditProviderRequested,
    required this.onAddModelRequested,
    required this.onEditModelRequested,
  });

  final LlmProviderConfig provider;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final void Function(LlmProviderConfig provider, LlmProviderModelConfig model)
  onEditModelRequested;

  @override
  ConsumerState<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends ConsumerState<_ProviderTile> {
  bool _modelsExpanded = false;

  @override
  void didUpdateWidget(covariant _ProviderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.models.isEmpty &&
        widget.provider.models.isNotEmpty) {
      _modelsExpanded = true;
      return;
    }
    if (widget.provider.models.isEmpty && _modelsExpanded) {
      _modelsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.provider;
    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: ValueKey('add-model-${provider.id}'),
          onPressed: () => widget.onAddModelRequested(provider),
          icon: const Icon(Icons.add_rounded),
          label: const Text('新增模型'),
        ),
        OutlinedButton.icon(
          key: ValueKey('edit-provider-${provider.id}'),
          onPressed: () => widget.onEditProviderRequested(provider),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑服务商'),
        ),
        OutlinedButton.icon(
          key: ValueKey('delete-provider-${provider.id}'),
          onPressed: () async {
            await ref
                .read(llmProviderConfigsProvider.notifier)
                .deleteProviderById(provider.id);
            for (final model in provider.models) {
              await ref
                  .read(chatDefaultsProvider.notifier)
                  .clearRememberedModelIdIfMatches(model.id);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('服务商已删除')));
            }
          },
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除服务商'),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 640;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact) ...[
                  _ProviderInfo(provider: provider),
                  const SizedBox(height: 12),
                  actionButtons,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ProviderInfo(provider: provider)),
                      const SizedBox(width: 12),
                      Flexible(child: actionButtons),
                    ],
                  ),
                const SizedBox(height: 12),
                if (provider.models.isEmpty)
                  Text('当前服务商下还没有模型。', style: theme.textTheme.bodyMedium)
                else ...[
                  OutlinedButton.icon(
                    key: ValueKey('provider-models-toggle-${provider.id}'),
                    onPressed: () {
                      setState(() {
                        _modelsExpanded = !_modelsExpanded;
                      });
                    },
                    icon: Icon(
                      _modelsExpanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                    ),
                    label: Text(
                      _modelsExpanded
                          ? '收起模型（${provider.models.length}）'
                          : '展开模型（${provider.models.length}）',
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 167),
                    alignment: Alignment.topCenter,
                    child: _modelsExpanded
                        ? Padding(
                            key: ValueKey(
                              'provider-models-panel-${provider.id}',
                            ),
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              children: [
                                for (final model in provider.models)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ProviderModelTile(
                                      provider: provider,
                                      model: model,
                                      onEditModelRequested:
                                          widget.onEditModelRequested,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProviderModelTile extends ConsumerWidget {
  const _ProviderModelTile({
    required this.provider,
    required this.model,
    required this.onEditModelRequested,
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
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('模型已删除')));
            }
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
                  _ProviderModelInfo(model: model),
                  const SizedBox(height: 12),
                  actionButtons,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ProviderModelInfo(model: model)),
                      const SizedBox(width: 8),
                      Flexible(child: actionButtons),
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

class _ProviderInfo extends StatelessWidget {
  const _ProviderInfo({required this.provider});

  final LlmProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(provider.name, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProviderMetaChip(
              icon: Icons.hub_outlined,
              label: '模型数量：${provider.models.length}',
            ),
            Tooltip(
              message: provider.apiUrl,
              child: _ProviderMetaChip(
                icon: Icons.link_rounded,
                label: 'API URL：${_buildApiUrlLabel(provider.apiUrl)}',
              ),
            ),
            _ProviderMetaChip(
              icon: Icons.key_outlined,
              label: 'API Key：${_maskApiKey(provider.apiKey)}',
            ),
          ],
        ),
        if (provider.models.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '模型摘要：${_buildModelSummary(provider.models)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _buildApiUrlLabel(String apiUrl) {
    final uri = Uri.tryParse(apiUrl.trim());
    final host = uri?.host.trim() ?? '';
    return host.isNotEmpty ? host : apiUrl.trim();
  }

  String _buildModelSummary(List<LlmProviderModelConfig> models) {
    if (models.isEmpty) {
      return '无';
    }
    const previewLimit = 2;
    final preview = models
        .take(previewLimit)
        .map((model) => model.displayName)
        .join('、');
    final remainingCount = models.length - previewLimit;
    if (remainingCount <= 0) {
      return preview;
    }
    return '$preview 等 $remainingCount 个模型';
  }

  String _maskApiKey(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.length <= 8) {
      return '已保存';
    }

    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }
}

class _ProviderModelInfo extends StatelessWidget {
  const _ProviderModelInfo({required this.model});

  final LlmProviderModelConfig model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(model.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProviderMetaChip(
              icon: Icons.memory_rounded,
              label: 'API 模型名称：${model.modelName}',
            ),
            if (model.supportsReasoning)
              const _ProviderMetaChip(
                icon: Icons.psychology_alt_outlined,
                label: '支持深度思考',
              ),
          ],
        ),
      ],
    );
  }
}

class _ProviderMetaChip extends StatelessWidget {
  const _ProviderMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
