import 'package:equatable/equatable.dart';

/// Settings transfer section 的稳定 key。
final class SettingsTransferKey extends Equatable {
  const SettingsTransferKey(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

/// Settings transfer 使用的稳定分组。
enum SettingsTransferGroup {
  providers('providers', '服务商', 0),
  presets('presets', '预设', 1),
  prompts('prompts', '提示词', 2),
  network('network', '网络', 3),
  outputProcessing('outputProcessing', '输出处理', 4),
  other('other', '其它', 5);

  const SettingsTransferGroup(this.wireKey, this.label, this.order);

  final String wireKey;
  final String label;
  final int order;
}

enum SettingsTransferSensitivity { standard, credentialBearing }

enum SettingsTransferSummaryAction { add, replace, clear }

/// 导出或导入确认界面使用的安全摘要项。
final class SettingsTransferSummaryItem extends Equatable {
  const SettingsTransferSummaryItem({
    required this.key,
    required this.label,
    required this.action,
    this.count,
  }) : assert(
         action == SettingsTransferSummaryAction.add
             ? count != null && count > 0
             : count == null,
       );

  final SettingsTransferKey key;
  final String label;
  final SettingsTransferSummaryAction action;
  final int? count;

  String get trailingText => switch (action) {
    SettingsTransferSummaryAction.add => '新增 $count 项',
    SettingsTransferSummaryAction.replace => '替换',
    SettingsTransferSummaryAction.clear => '清空',
  };

  @override
  List<Object?> get props => [key, label, action, count];
}
