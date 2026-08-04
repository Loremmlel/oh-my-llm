import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';

/// Settings 同步时选择的四类数据。
final class SettingsSyncSelection {
  const SettingsSyncSelection({
    this.providers = false,
    this.presets = false,
    this.prompts = false,
    this.other = false,
  });

  final bool providers;
  final bool presets;
  final bool prompts;
  final bool other;
}

/// Sync 对 Settings 的单一聚合边界。
abstract interface class SettingsSyncFacade {
  SettingsExportData exportSelected(SettingsSyncSelection selection);

  SettingsExportData deduplicateIncoming(SettingsExportData data);

  Future<bool> importDeduplicated(SettingsExportData data);
}

/// 必须由 app composition 或测试显式绑定的 Settings 同步实现。
final settingsSyncFacadeProvider = Provider<SettingsSyncFacade>((ref) {
  throw StateError('SettingsSyncFacade 尚未由应用组合层绑定');
});
