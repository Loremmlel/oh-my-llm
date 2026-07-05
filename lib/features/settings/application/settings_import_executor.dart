import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings_export_data.dart';
import 'auto_retry_settings_controller.dart';
import 'custom_headers_controller.dart';
import 'font_size_settings_controller.dart';
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
/// 每个分类仅在数据非空时写入，避免无意义的覆盖。
/// 返回 `true` 表示至少写入了一项，`false` 表示全部跳过。
///
/// [ref] 接受 [Ref] 类型——在 Riverpod 3.x 中 [WidgetRef] 是 [Ref] 的子类型，
/// 因此 Widget 和 Notifier 均可直接传入 `ref` 调用本方法。
class SettingsImportExecutor {
  const SettingsImportExecutor();

  /// [ref] 同时兼容 [Ref]（Notifier 内）与 [WidgetRef]（Widget 内）。
  Future<bool> executeImport(dynamic ref, {required SettingsExportData data}) async {
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
    if (data.customHeadersConfig != null) {
      await ref
          .read(customHeadersProvider.notifier)
          .save(data.customHeadersConfig!);
      wrote = true;
    }
    if (data.fontSizeSettings != null) {
      await ref
          .read(fontSizeSettingsProvider.notifier)
          .save(data.fontSizeSettings!);
      wrote = true;
    }
    return wrote;
  }
}
