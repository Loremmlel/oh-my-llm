import 'package:equatable/equatable.dart';

import 'sync_protocol_version.dart';

/// 可安全展示或跨 HTTP 传输的协议失败码。
enum SyncProtocolErrorCode {
  malformedMessage,
  unsupportedProtocol,
  pairingRequired,
  pairingRejected,
  sessionInvalid,
  sessionExpired,
  authorizationRequired,
  sensitiveConfirmationRequired,
  replayRejected,
  unsupportedSettingsFormat,
  requestTimedOut,
  serverBusy,
}

/// 不携带异常、密文或秘密的失败对象。
final class SyncProtocolFailure extends Equatable implements Exception {
  const SyncProtocolFailure(
    this.code, {
    this.minimumProtocolVersion,
    this.maximumProtocolVersion,
  });

  final SyncProtocolErrorCode code;
  final int? minimumProtocolVersion;
  final int? maximumProtocolVersion;

  String get userMessage => switch (code) {
    SyncProtocolErrorCode.malformedMessage => '同步请求格式无效',
    SyncProtocolErrorCode.unsupportedProtocol => '设备版本不兼容，需要更新',
    SyncProtocolErrorCode.pairingRequired => '此设备尚未配对',
    SyncProtocolErrorCode.pairingRejected => '配对失败，请重新生成配对码后重试',
    SyncProtocolErrorCode.sessionInvalid => '同步会话无效，请重新连接',
    SyncProtocolErrorCode.sessionExpired => '同步会话已过期，请重新连接',
    SyncProtocolErrorCode.authorizationRequired => '服务端尚未授权所选同步内容',
    SyncProtocolErrorCode.sensitiveConfirmationRequired => '敏感凭据同步需要明确确认',
    SyncProtocolErrorCode.replayRejected => '同步消息已失效，请重新连接',
    SyncProtocolErrorCode.unsupportedSettingsFormat => '设置数据版本不兼容',
    SyncProtocolErrorCode.requestTimedOut => '请求处理超时，请重试',
    SyncProtocolErrorCode.serverBusy => '服务端暂时繁忙，请稍后重试',
  };

  SyncProtocolRange? get supportedRange =>
      minimumProtocolVersion == null || maximumProtocolVersion == null
      ? null
      : SyncProtocolRange(
          minimum: minimumProtocolVersion!,
          maximum: maximumProtocolVersion!,
        );

  @override
  List<Object?> get props => [
    code,
    minimumProtocolVersion,
    maximumProtocolVersion,
  ];

  @override
  String toString() => userMessage;
}
