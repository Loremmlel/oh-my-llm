import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../../application/preferences/chat_defaults_controller.dart';
import '../../../../application/providers/llm_model_configs_controller.dart';
import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_helpers.dart';
import '../model_capability_chips.dart';
import '../../shared/settings_table_row.dart';

class ProviderModelTile extends ConsumerStatefulWidget {
  static const columnFlexes = [3, 4, 2, 2, 3];
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
  ConsumerState<ProviderModelTile> createState() => _ProviderModelTileState();
}

class _ProviderModelTileState extends ConsumerState<ProviderModelTile> {
  bool _isSaving = false;
  String? _error;

  Future<void> _setCapability({bool? reasoning, bool? image}) async {
    if (_isSaving) return;
    final provider = ref
        .read(llmProviderConfigsProvider)
        .where((item) => item.id == widget.provider.id)
        .firstOrNull;
    final model = provider?.models
        .where((item) => item.id == widget.model.id)
        .firstOrNull;
    if (model == null) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref
          .read(llmProviderConfigsProvider.notifier)
          .upsertModel(
            providerId: widget.provider.id,
            model: model.copyWith(
              supportsReasoning: reasoning,
              supportsImageInput: image,
            ),
          );
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final model = widget.model;
    final theme = Theme.of(context);
    final menu = PopupMenuButton<String>(
      tooltip: '模型操作',
      enabled: !_isSaving,
      onSelected: (action) async {
        if (action == 'edit') {
          widget.onEditModelRequested(provider, model);
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
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            AppBreakpoints.contentMasterDetail;
        final name = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: model.displayName,
              child: Text(
                model.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Tooltip(
              message: model.modelName,
              child: Text(
                model.modelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
        final capabilities = ModelCapabilityChips(
          supportsReasoning: model.supportsReasoning,
          supportsImageInput: model.supportsImageInput,
          onReasoningChanged: _isSaving
              ? null
              : (value) => _setCapability(reasoning: value),
          onImageInputChanged: _isSaving
              ? null
              : (value) => _setCapability(image: value),
        );
        final edit = TextButton.icon(
          onPressed: _isSaving
              ? null
              : () => widget.onEditModelRequested(provider, model),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('编辑'),
        );
        if (!compact) {
          Widget capability(
            String label,
            bool value,
            ValueChanged<bool> onChanged,
          ) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              label: '${model.displayName} $label',
              child: Checkbox(
                value: value,
                onChanged: _isSaving ? null : (v) => onChanged(v!),
              ),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsTableRow(
                flexes: ProviderModelTile.columnFlexes,
                cells: [
                  Tooltip(
                    message: model.displayName,
                    child: Text(
                      model.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Tooltip(
                    message: model.modelName,
                    child: Text(
                      model.modelName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  capability(
                    '深度思考',
                    model.supportsReasoning,
                    (v) => _setCapability(reasoning: v),
                  ),
                  capability(
                    '图像',
                    model.supportsImageInput,
                    (v) => _setCapability(image: v),
                  ),
                  Row(children: [edit, menu]),
                ],
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs,
            horizontal: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: name),
                  edit,
                  menu,
                ],
              ),
              capabilities,
              const Divider(height: 1),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
