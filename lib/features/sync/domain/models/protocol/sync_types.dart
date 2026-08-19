import 'package:equatable/equatable.dart';

/// Sync v4 wire payload 使用的稳定设置分组 ID。
final class SettingsSyncGroupId extends Equatable {
  const SettingsSyncGroupId(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
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
