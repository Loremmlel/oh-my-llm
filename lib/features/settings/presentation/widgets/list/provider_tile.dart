import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/chat_defaults_controller.dart';
import '../../../application/llm_model_configs_controller.dart';
import '../../../domain/models/llm_provider_config.dart';
import 'provider_info.dart';
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
                  ProviderInfo(provider: provider),
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
                              provider.name,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: actionButtons,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ProviderInfoBody(provider: provider),
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
                                    child: ProviderModelTile(
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
