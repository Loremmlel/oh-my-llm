import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../../application/preferences/chat_defaults_controller.dart';
import '../../../../application/providers/llm_model_configs_controller.dart';
import '../../../../domain/models/providers/llm_provider_config.dart';
import '../../shared/settings_helpers.dart';
import '../model_capability_chips.dart';

class ProviderModelTile extends ConsumerStatefulWidget {
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
        final compact = AppBreakpoints.useCompactFormActions(
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1),
        );
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
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: name),
                  if (!compact) ...[
                    const SizedBox(width: AppSpacing.sm),
                    capabilities,
                  ],
                  menu,
                ],
              ),
              if (compact) capabilities,
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
