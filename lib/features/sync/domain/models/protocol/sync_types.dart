import 'package:equatable/equatable.dart';

/// Sync v4 wire payload 使用的稳定设置分组 ID。
final class SettingsSyncGroupId extends Equatable {
  const SettingsSyncGroupId(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

/// v4 迁移期间保留的 presentation 兼容分类；Task 8 将移除。
@Deprecated('仅供 Task 7 的旧四分类 presentation adapter 使用。')
enum SyncCategory {
  providers,
  presets,
  prompts,
  other;

  String get label => switch (this) {
    providers => '服务商',
    presets => '预设',
    prompts => '提示词',
    other => '其它',
  };

  /// 旧 presentation adapter 映射所用的稳定标识；v4 wire 直接使用 group ID。
  String get payloadKey => switch (this) {
    providers => 'providers',
    presets => 'presets',
    prompts => 'prompts',
    other => 'other',
  };
}

/// 仅供旧 presentation adapter 使用，不参与 v4 wire 或 server security。
@Deprecated('Sync v4 使用 SettingsSyncSensitivity 和 catalog descriptor。')
enum SyncCategorySensitivity { standard, credentialBearing }

@Deprecated('Sync v4 使用 SettingsSyncGroupId；Task 8 将移除。')
extension SyncCategorySecurity on SyncCategory {
  SyncCategorySensitivity get sensitivity => switch (this) {
    SyncCategory.providers ||
    SyncCategory.other => SyncCategorySensitivity.credentialBearing,
    SyncCategory.presets ||
    SyncCategory.prompts => SyncCategorySensitivity.standard,
  };

  bool get isCredentialBearing =>
      sensitivity == SyncCategorySensitivity.credentialBearing;
}

/// 仅用于隔离的 v1 rejection fixture；生产 Sync v4 不得引用这些值。
@Deprecated('Sync v1 已被拒绝；请使用 SyncProtocolMessage。')
final class SyncMessageType {
  const SyncMessageType._();

  static const String settingsSyncRequest = 'settings_sync_request';
  static const String settingsSyncResponse = 'settings_sync_response';
  static const String syncAck = 'sync_ack';
  static const String error = 'error';
}

/// 仅用于隔离 v1 fixture；生产错误使用 SyncProtocolErrorCode。
@Deprecated('Sync v1 已被拒绝；请使用 SyncProtocolErrorCode。')
final class SyncErrorCode {
  const SyncErrorCode._();

  static const int unknownType = 1;
  static const int payloadParseFailed = 2;
  static const int serverBusy = 3;
  static const int timeout = 4;
}
