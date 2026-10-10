import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';

import '../../shared/settings_table_row.dart';

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
    this.onBatchAddModelsRequested,
    super.key,
  });
  final LlmProviderConfig provider;
  final ValueChanged<LlmProviderConfig> onEditProviderRequested;
  final ValueChanged<LlmProviderConfig> onAddModelRequested;
  final ValueChanged<LlmProviderConfig>? onBatchAddModelsRequested;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            AppBreakpoints.contentMasterDetail;
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              key: ValueKey('add-model-${provider.id}'),
              onPressed: () => widget.onAddModelRequested(provider),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增模型'),
            ),
            if (!compact)
              TextButton.icon(
                onPressed: () =>
                    (widget.onBatchAddModelsRequested ??
                    widget.onAddModelRequested)(provider),
                icon: const Icon(Icons.library_add_outlined, size: 18),
                label: const Text('批量添加'),
              ),
            if (!compact)
              TextButton.icon(
                onPressed: () => widget.onEditProviderRequested(provider),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            PopupMenuButton<String>(
              tooltip: '服务商操作',
              onSelected: (action) {
                if (action == 'edit') widget.onEditProviderRequested(provider);
                if (action == 'batch') {
                  (widget.onBatchAddModelsRequested ??
                      widget.onAddModelRequested)(provider);
                }
                if (action == 'delete') _delete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑服务商')),
                if (compact)
                  const PopupMenuItem(value: 'batch', child: Text('批量添加模型')),
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
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('provider-models-toggle-${provider.id}'),
                      tooltip:
                          '${_modelsExpanded ? '收起' : '展开'}模型（${provider.models.length}）',
                      onPressed: () =>
                          setState(() => _modelsExpanded = !_modelsExpanded),
                      icon: Icon(
                        _modelsExpanded
                            ? Icons.expand_more
                            : Icons.chevron_right,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (compact)
                            Text(
                              '${provider.models.length} 个模型 · ${provider.apiProtocol.displayName}',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      Text(
                        '${provider.models.length} 个模型',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Text(
                        provider.apiProtocol.displayName,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      actions,
                    ],
                  ],
                ),
              ),
              if (compact)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actions,
                ),
              if (_modelsExpanded) ...[
                const Divider(height: 1),
                ProviderInfoBody(
                  provider: provider,
                  onEdit: () => widget.onEditProviderRequested(provider),
                ),
                if (provider.models.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text('还没有模型，点击“新增模型”开始配置。'),
                  ),
                if (!compact && provider.models.isNotEmpty)
                  const SettingsTableRow(
                    header: true,
                    flexes: ProviderModelTile.columnFlexes,
                    cells: [
                      Text('名称'),
                      Text('模型 ID'),
                      AppHelpTitle(
                        title: '深度思考',
                        message: '声明模型支持深度思考，聊天页据此显示思考选项。',
                      ),
                      AppHelpTitle(
                        title: '图像',
                        message: '仅在模型支持图像输入时开启；关闭后不能发送含图的上下文。',
                      ),
                      Text('操作'),
                    ],
                  ),
                for (final model in provider.models)
                  ProviderModelTile(
                    key: ValueKey(model.id),
                    provider: provider,
                    model: model,
                    onEditModelRequested: widget.onEditModelRequested,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
