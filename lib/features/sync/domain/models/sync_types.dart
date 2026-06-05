/// 同步协议的消息类型常量。
class SyncMessageType {
  SyncMessageType._();

  static const String settingsSyncRequest = 'settings_sync_request';
  static const String settingsSyncResponse = 'settings_sync_response';
  static const String syncAck = 'sync_ack';
  static const String error = 'error';
}

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
  String get payloadKey => name;
}

/// 同步协议错误码。
class SyncErrorCode {
  SyncErrorCode._();

  static const int unknownType = 1;
  static const int payloadParseFailed = 2;
  static const int serverBusy = 3;
  static const int timeout = 4;
}
