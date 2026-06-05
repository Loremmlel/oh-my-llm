import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings_export_data.dart';
import 'auto_retry_settings_controller.dart';
import 'fixed_prompt_sequences_controller.dart';
import 'llm_model_configs_controller.dart';
import 'memory_prompts_controller.dart';
import 'preset_prompts_controller.dart';
import 'template_prompts_controller.dart';

/// 设置导入的统一写入执行器。
///
/// 将去重后的 [SettingsExportData] 按分类写入各 controller，
/// 被 `ImportConfirmDialog` 与 `SyncClientController.executeImport` 共同复用。
///
/// 由于 Riverpod 的 [Ref]（Notifier 上下文）与 [WidgetRef]（widget 上下文）
/// 不共享公共接口，本类提供两个方法：
///
/// - [executeImport]     接收 [Ref]，供 Notifier / ProviderContainer 使用。
/// - [executeImportFromWidget] 接收 [WidgetRef]，供 widget 使用。
///
/// 两者行为完全一致。每个分类仅在数据非空时写入，避免无意义的覆盖。
/// 返回 `true` 表示至少写入了一项，`false` 表示全部跳过。
class SettingsImportExecutor {
  const SettingsImportExecutor();

  Future<bool> executeImport(Ref ref, {required SettingsExportData data}) async {
    var wrote = false;
    if (data.modelProviders.isNotEmpty) {
      await ref
          .read(llmProviderConfigsProvider.notifier)
          .mergeImportedProviders(data.modelProviders);
      wrote = true;
    }
    if (data.memoryPrompts.isNotEmpty) {
      await ref.read(memoryPromptsProvider.notifier).upsertAll(data.memoryPrompts);
      wrote = true;
    }
    if (data.presetPrompts.isNotEmpty) {
      await ref
          .read(presetPromptsProvider.notifier)
          .upsertAll(data.presetPrompts);
      wrote = true;
    }
    if (data.templatePrompts.isNotEmpty) {
      await ref
          .read(templatePromptsProvider.notifier)
          .upsertAll(data.templatePrompts);
      wrote = true;
    }
    if (data.fixedPromptSequences.isNotEmpty) {
      await ref
          .read(fixedPromptSequencesProvider.notifier)
          .upsertAll(data.fixedPromptSequences);
      wrote = true;
    }
    if (data.autoRetrySettings != null) {
      await ref
          .read(autoRetrySettingsProvider.notifier)
          .save(data.autoRetrySettings!);
      wrote = true;
    }
    return wrote;
  }

  Future<bool> executeImportFromWidget(
    WidgetRef ref, {
    required SettingsExportData data,
  }) async {
    var wrote = false;
    if (data.modelProviders.isNotEmpty) {
      await ref
          .read(llmProviderConfigsProvider.notifier)
          .mergeImportedProviders(data.modelProviders);
      wrote = true;
    }
    if (data.memoryPrompts.isNotEmpty) {
      await ref.read(memoryPromptsProvider.notifier).upsertAll(data.memoryPrompts);
      wrote = true;
    }
    if (data.presetPrompts.isNotEmpty) {
      await ref
          .read(presetPromptsProvider.notifier)
          .upsertAll(data.presetPrompts);
      wrote = true;
    }
    if (data.templatePrompts.isNotEmpty) {
      await ref
          .read(templatePromptsProvider.notifier)
          .upsertAll(data.templatePrompts);
      wrote = true;
    }
    if (data.fixedPromptSequences.isNotEmpty) {
      await ref
          .read(fixedPromptSequencesProvider.notifier)
          .upsertAll(data.fixedPromptSequences);
      wrote = true;
    }
    if (data.autoRetrySettings != null) {
      await ref
          .read(autoRetrySettingsProvider.notifier)
          .save(data.autoRetrySettings!);
      wrote = true;
    }
    return wrote;
  }
}
