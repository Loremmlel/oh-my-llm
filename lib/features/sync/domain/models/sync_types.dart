/// 可同步的设置分类。
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

  /// 协议中使用的传输标识。
  String get payloadKey => switch (this) {
    providers => 'providers',
    presets => 'presets',
    prompts => 'prompts',
    other => 'other',
  };
}

/// 同步分类的敏感等级。
///
/// 此处是协议和界面共用的唯一事实源，避免因为显示文案变化而遗漏凭据确认。
enum SyncCategorySensitivity { standard, credentialBearing }

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

/// 仅用于隔离的 v1 rejection fixture；生产 Sync v2 不得引用这些值。
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
