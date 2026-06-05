import 'dart:convert';

import '../../../../core/utils/id_generator.dart';
import 'sync_types.dart';

/// 同步协议的泛型消息信封。
///
/// 传输层仅负责编解码此结构，不感知具体消息类型。
/// 未来新增消息类型只需在 [SyncMessageType] 中注册并约定 payload 字段。
class SyncMessage {
  const SyncMessage({
    required this.type,
    required this.requestId,
    required this.payload,
    this.version = 1,
  });

  /// 消息类型标识，见 [SyncMessageType]。
  final String type;

  /// 协议版本。
  final int version;

  /// 请求关联 ID，用于匹配请求与响应。
  final String requestId;

  /// 消息负载，具体结构由 [type] 决定。
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'type': type,
    'version': version,
    'requestId': requestId,
    'payload': payload,
  };

  static SyncMessage? tryFromJson(Map<String, dynamic> json) {
    try {
      final type = json['type'] as String?;
      final requestId = json['requestId'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;
      if (type == null || requestId == null || payload == null) return null;
      return SyncMessage(
        type: type,
        version: (json['version'] as int?) ?? 1,
        requestId: requestId,
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }

  /// 构建一条新的请求消息，自动生成 [requestId]。
  factory SyncMessage.request({
    required String type,
    required Map<String, dynamic> payload,
  }) {
    return SyncMessage(
      type: type,
      requestId: generateEntityId(),
      payload: payload,
    );
  }

  /// 构建一条响应消息，关联到原始请求的 [requestId]。
  factory SyncMessage.response({
    required String type,
    required String requestId,
    required Map<String, dynamic> payload,
  }) {
    return SyncMessage(
      type: type,
      requestId: requestId,
      payload: payload,
    );
  }

  /// 构建一条错误消息。
  factory SyncMessage.error({
    required String requestId,
    required int code,
    required String message,
  }) {
    return SyncMessage(
      type: SyncMessageType.error,
      requestId: requestId,
      payload: {'code': code, 'message': message},
    );
  }
}

/// 同步消息的 JSON 编解码器。
class SyncMessageCodec {
  SyncMessageCodec._();

  static String encode(SyncMessage message) => jsonEncode(message.toJson());

  static SyncMessage? tryDecode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return SyncMessage.tryFromJson(json);
    } catch (_) {
      return null;
    }
  }
}
