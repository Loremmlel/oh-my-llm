import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../settings/domain/models/settings_export_codec.dart';
import '../../../settings/domain/models/settings_export_data.dart';
import 'sync_protocol_failure.dart';
import 'sync_protocol_version.dart';
import 'sync_types.dart';

/// v2 wire message 的封闭类型集合。解析完成后不再向调用方暴露动态 Map。
sealed class SyncProtocolMessage extends Equatable {
  const SyncProtocolMessage({
    required this.requestId,
    this.protocolVersion = SyncProtocolVersionPolicy.current,
  });

  final int protocolVersion;
  final String requestId;
  String get kind;

  @override
  List<Object?> get props => [protocolVersion, requestId, kind];
}

final class PairingChallengeRequest extends SyncProtocolMessage {
  const PairingChallengeRequest({
    required super.requestId,
    required this.clientIdentity,
  });

  final String clientIdentity;
  @override
  String get kind => 'pairingChallengeRequest';

  @override
  List<Object?> get props => [...super.props, clientIdentity];
}

final class PairingChallengeResponse extends SyncProtocolMessage {
  const PairingChallengeResponse({
    required super.requestId,
    required this.pairingId,
    required this.challengeNonce,
    required this.serverIdentity,
    this.minimumProtocolVersion = SyncProtocolVersionPolicy.minimumSupported,
    this.maximumProtocolVersion = SyncProtocolVersionPolicy.maximumSupported,
  });

  final String pairingId;
  final String challengeNonce;
  final String serverIdentity;
  final int minimumProtocolVersion;
  final int maximumProtocolVersion;
  @override
  String get kind => 'pairingChallengeResponse';

  @override
  List<Object?> get props => [
    ...super.props,
    pairingId,
    challengeNonce,
    serverIdentity,
    minimumProtocolVersion,
    maximumProtocolVersion,
  ];
}

final class PairingProofRequest extends SyncProtocolMessage {
  const PairingProofRequest({
    required super.requestId,
    required this.pairingId,
    required this.clientIdentity,
    required this.clientDisplayName,
    required this.clientNonce,
    required this.proof,
  });

  final String pairingId;
  final String clientIdentity;
  final String clientDisplayName;
  final String clientNonce;
  final String proof;
  @override
  String get kind => 'pairingProofRequest';

  @override
  List<Object?> get props => [
    ...super.props,
    pairingId,
    clientIdentity,
    clientDisplayName,
    clientNonce,
    proof,
  ];
}

final class PairingProofResponse extends SyncProtocolMessage {
  const PairingProofResponse({
    required super.requestId,
    required this.serverIdentity,
    required this.proof,
  });

  final String serverIdentity;
  final String proof;
  @override
  String get kind => 'pairingProofResponse';

  @override
  List<Object?> get props => [...super.props, serverIdentity, proof];
}

final class SessionOpenRequest extends SyncProtocolMessage {
  const SessionOpenRequest({
    required super.requestId,
    required this.peerId,
    required this.clientNonce,
    required this.proof,
  });

  final String peerId;
  final String clientNonce;
  final String proof;
  @override
  String get kind => 'sessionOpenRequest';

  @override
  List<Object?> get props => [...super.props, peerId, clientNonce, proof];
}

final class SessionOpenResponse extends SyncProtocolMessage {
  const SessionOpenResponse({
    required super.requestId,
    required this.sessionId,
    required this.sessionToken,
    required this.serverNonce,
    required this.proof,
  });

  final String sessionId;
  final String sessionToken;
  final String serverNonce;
  final String proof;
  @override
  String get kind => 'sessionOpenResponse';

  @override
  List<Object?> get props => [
    ...super.props,
    sessionId,
    sessionToken,
    serverNonce,
    proof,
  ];
}

/// 已配对业务消息的共同外壳；密文的关联数据由所有这些公开字段组成。
sealed class EncryptedSyncMessage extends SyncProtocolMessage {
  const EncryptedSyncMessage({
    required super.requestId,
    required this.sessionId,
    required this.sessionToken,
    required this.issuedAtMs,
    required this.nonce,
    required this.ciphertext,
  });

  final String sessionId;
  final String sessionToken;
  final int issuedAtMs;
  final String nonce;
  final String ciphertext;

  @override
  List<Object?> get props => [
    ...super.props,
    sessionId,
    sessionToken,
    issuedAtMs,
    nonce,
    ciphertext,
  ];
}

final class EncryptedSyncRequest extends EncryptedSyncMessage {
  const EncryptedSyncRequest({
    required super.requestId,
    required super.sessionId,
    required super.sessionToken,
    required super.issuedAtMs,
    required super.nonce,
    required super.ciphertext,
  });

  @override
  String get kind => 'encryptedSyncRequest';
}

final class EncryptedSyncResponse extends EncryptedSyncMessage {
  const EncryptedSyncResponse({
    required super.requestId,
    required super.sessionId,
    required super.sessionToken,
    required super.issuedAtMs,
    required super.nonce,
    required super.ciphertext,
  });

  @override
  String get kind => 'encryptedSyncResponse';
}

/// 在认证前也可返回的最小公开错误，绝不带 payload、异常文本或秘密。
final class SyncProtocolError extends SyncProtocolMessage {
  const SyncProtocolError({required super.requestId, required this.failure});

  final SyncProtocolFailure failure;
  @override
  String get kind => 'error';

  @override
  List<Object?> get props => [...super.props, failure];
}

sealed class EncryptedSyncPayload extends Equatable {
  const EncryptedSyncPayload();
  String get kind;
}

final class SettingsSyncRequestPayload extends EncryptedSyncPayload {
  SettingsSyncRequestPayload(
    Set<SyncCategory> categories, {
    required this.confirmedSensitive,
  }) : categories = Set.unmodifiable(categories);

  final Set<SyncCategory> categories;
  final bool confirmedSensitive;
  @override
  String get kind => 'settingsSyncRequest';

  @override
  List<Object?> get props => [
    categories.map((item) => item.index).toList()..sort(),
    confirmedSensitive,
  ];
}

final class SettingsSnapshotPayload extends Equatable {
  const SettingsSnapshotPayload({
    required this.formatVersion,
    required this.data,
  });

  final int formatVersion;
  final SettingsExportData data;

  @override
  List<Object?> get props => [formatVersion, data.toJsonString()];
}

final class SettingsSyncResponsePayload extends EncryptedSyncPayload {
  const SettingsSyncResponsePayload(this.snapshot);

  final SettingsSnapshotPayload snapshot;
  @override
  String get kind => 'settingsSyncResponse';

  @override
  List<Object?> get props => [snapshot];
}

/// Codec 的错误不会泄漏原始 JSON；handler 可直接映射到 public error。
sealed class SyncProtocolDecodeResult {
  const SyncProtocolDecodeResult();
}

final class SyncProtocolDecodeSuccess extends SyncProtocolDecodeResult {
  const SyncProtocolDecodeSuccess(this.message);
  final SyncProtocolMessage message;
}

final class SyncProtocolDecodeFailure extends SyncProtocolDecodeResult {
  const SyncProtocolDecodeFailure(this.failure);
  final SyncProtocolFailure failure;
}

/// Sync v2 唯一 JSON 边界。字段类型、ID、base64 和分类均严格验证。
final class SyncProtocolCodec {
  const SyncProtocolCodec._();

  static String encode(SyncProtocolMessage message) =>
      jsonEncode(_messageJson(message));

  static SyncProtocolDecodeResult decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return _malformed();
      return decodeObject(Map<String, Object?>.from(value));
    } catch (_) {
      return _malformed();
    }
  }

  static SyncProtocolDecodeResult decodeObject(Map<String, Object?> raw) {
    try {
      final version = _int(raw, 'protocolVersion');
      final compatible = SyncProtocolVersionPolicy.check(version);
      if (!compatible.isSupported) {
        return SyncProtocolDecodeFailure(
          SyncProtocolFailure(
            SyncProtocolErrorCode.unsupportedProtocol,
            minimumProtocolVersion: SyncProtocolVersionPolicy.minimumSupported,
            maximumProtocolVersion: SyncProtocolVersionPolicy.maximumSupported,
          ),
        );
      }
      final requestId = _id(raw, 'requestId');
      final kind = _id(raw, 'kind');
      return SyncProtocolDecodeSuccess(
        _readMessage(raw, kind, requestId, version),
      );
    } catch (_) {
      return _malformed();
    }
  }

  static Map<String, Object?> payloadToJson(EncryptedSyncPayload payload) =>
      switch (payload) {
        SettingsSyncRequestPayload(
          :final categories,
          :final confirmedSensitive,
        ) =>
          {
            'kind': payload.kind,
            'categories': categories.map((item) => item.payloadKey).toList(),
            'confirmedSensitive': confirmedSensitive,
          },
        SettingsSyncResponsePayload(:final snapshot) => {
          'kind': payload.kind,
          'snapshot': {
            'formatVersion': snapshot.formatVersion,
            'data': snapshot.data.toJson(),
          },
        },
      };

  static EncryptedSyncPayload? tryDecodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _readPayload(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static String encodePayload(EncryptedSyncPayload payload) =>
      jsonEncode(payloadToJson(payload));

  static Map<String, Object?> aadJson(EncryptedSyncMessage message) => {
    'protocolVersion': message.protocolVersion,
    'kind': message.kind,
    'requestId': message.requestId,
    'sessionId': message.sessionId,
    'sessionToken': message.sessionToken,
    'issuedAtMs': message.issuedAtMs,
    'nonce': message.nonce,
  };

  static String canonicalAad(EncryptedSyncMessage message) =>
      jsonEncode(aadJson(message));

  static SyncProtocolDecodeFailure _malformed() =>
      const SyncProtocolDecodeFailure(
        SyncProtocolFailure(SyncProtocolErrorCode.malformedMessage),
      );

  static SyncProtocolMessage _readMessage(
    Map<String, Object?> raw,
    String kind,
    String requestId,
    int version,
  ) {
    switch (kind) {
      case 'pairingChallengeRequest':
        return PairingChallengeRequest(
          requestId: requestId,
          clientIdentity: _id(raw, 'clientIdentity'),
        );
      case 'pairingChallengeResponse':
        return PairingChallengeResponse(
          requestId: requestId,
          pairingId: _id(raw, 'pairingId'),
          challengeNonce: _base64(raw, 'challengeNonce'),
          serverIdentity: _id(raw, 'serverIdentity'),
          minimumProtocolVersion: _int(raw, 'minimumProtocolVersion'),
          maximumProtocolVersion: _int(raw, 'maximumProtocolVersion'),
        );
      case 'pairingProofRequest':
        return PairingProofRequest(
          requestId: requestId,
          pairingId: _id(raw, 'pairingId'),
          clientIdentity: _id(raw, 'clientIdentity'),
          clientDisplayName: _id(raw, 'clientDisplayName'),
          clientNonce: _base64(raw, 'clientNonce'),
          proof: _base64(raw, 'proof'),
        );
      case 'pairingProofResponse':
        return PairingProofResponse(
          requestId: requestId,
          serverIdentity: _id(raw, 'serverIdentity'),
          proof: _base64(raw, 'proof'),
        );
      case 'sessionOpenRequest':
        return SessionOpenRequest(
          requestId: requestId,
          peerId: _id(raw, 'peerId'),
          clientNonce: _base64(raw, 'clientNonce'),
          proof: _base64(raw, 'proof'),
        );
      case 'sessionOpenResponse':
        return SessionOpenResponse(
          requestId: requestId,
          sessionId: _id(raw, 'sessionId'),
          sessionToken: _base64(raw, 'sessionToken'),
          serverNonce: _base64(raw, 'serverNonce'),
          proof: _base64(raw, 'proof'),
        );
      case 'encryptedSyncRequest':
        return EncryptedSyncRequest(
          requestId: requestId,
          sessionId: _id(raw, 'sessionId'),
          sessionToken: _base64(raw, 'sessionToken'),
          issuedAtMs: _int(raw, 'issuedAtMs'),
          nonce: _base64(raw, 'nonce'),
          ciphertext: _base64(raw, 'ciphertext'),
        );
      case 'encryptedSyncResponse':
        return EncryptedSyncResponse(
          requestId: requestId,
          sessionId: _id(raw, 'sessionId'),
          sessionToken: _base64(raw, 'sessionToken'),
          issuedAtMs: _int(raw, 'issuedAtMs'),
          nonce: _base64(raw, 'nonce'),
          ciphertext: _base64(raw, 'ciphertext'),
        );
      case 'error':
        return SyncProtocolError(
          requestId: requestId,
          failure: _readFailure(raw),
        );
      default:
        throw const FormatException();
    }
  }

  static EncryptedSyncPayload _readPayload(Map<String, Object?> raw) {
    switch (_id(raw, 'kind')) {
      case 'settingsSyncRequest':
        final list = raw['categories'];
        if (list is! List || list.isEmpty) throw const FormatException();
        final categories = <SyncCategory>{};
        for (final value in list) {
          if (value is! String) throw const FormatException();
          final category = SyncCategory.values.where(
            (item) => item.payloadKey == value,
          );
          if (category.isEmpty || !categories.add(category.single)) {
            throw const FormatException();
          }
        }
        final rawConfirmedSensitive = raw['confirmedSensitive'];
        if (rawConfirmedSensitive != null && rawConfirmedSensitive is! bool) {
          throw const FormatException();
        }
        return SettingsSyncRequestPayload(
          categories,
          confirmedSensitive: rawConfirmedSensitive as bool? ?? false,
        );
      case 'settingsSyncResponse':
        final snapshot = raw['snapshot'];
        if (snapshot is! Map) throw const FormatException();
        final snapshotMap = Map<String, Object?>.from(snapshot);
        final data = snapshotMap['data'];
        if (data is! Map) throw const FormatException();
        final decoded = SettingsExportCodec.decode(
          Map<String, Object?>.from(data),
        );
        if (decoded is! SettingsExportDecodeSuccess) {
          throw const FormatException();
        }
        final formatVersion = _int(snapshotMap, 'formatVersion');
        if (formatVersion != decoded.sourceVersion ||
            formatVersion < SettingsExportCodec.minimumSupportedVersion ||
            formatVersion > SettingsExportCodec.maximumSupportedVersion) {
          throw const FormatException();
        }
        return SettingsSyncResponsePayload(
          SettingsSnapshotPayload(
            formatVersion: formatVersion,
            data: decoded.data,
          ),
        );
      default:
        throw const FormatException();
    }
  }

  static Map<String, Object?> _messageJson(SyncProtocolMessage message) {
    final map = <String, Object?>{
      'protocolVersion': message.protocolVersion,
      'kind': message.kind,
      'requestId': message.requestId,
    };
    switch (message) {
      case PairingChallengeRequest(:final clientIdentity):
        map['clientIdentity'] = clientIdentity;
      case PairingChallengeResponse(
        :final pairingId,
        :final challengeNonce,
        :final serverIdentity,
        :final minimumProtocolVersion,
        :final maximumProtocolVersion,
      ):
        map.addAll({
          'pairingId': pairingId,
          'challengeNonce': challengeNonce,
          'serverIdentity': serverIdentity,
          'minimumProtocolVersion': minimumProtocolVersion,
          'maximumProtocolVersion': maximumProtocolVersion,
        });
      case PairingProofRequest(
        :final pairingId,
        :final clientIdentity,
        :final clientDisplayName,
        :final clientNonce,
        :final proof,
      ):
        map.addAll({
          'pairingId': pairingId,
          'clientIdentity': clientIdentity,
          'clientDisplayName': clientDisplayName,
          'clientNonce': clientNonce,
          'proof': proof,
        });
      case PairingProofResponse(:final serverIdentity, :final proof):
        map.addAll({'serverIdentity': serverIdentity, 'proof': proof});
      case SessionOpenRequest(:final peerId, :final clientNonce, :final proof):
        map.addAll({
          'peerId': peerId,
          'clientNonce': clientNonce,
          'proof': proof,
        });
      case SessionOpenResponse(
        :final sessionId,
        :final sessionToken,
        :final serverNonce,
        :final proof,
      ):
        map.addAll({
          'sessionId': sessionId,
          'sessionToken': sessionToken,
          'serverNonce': serverNonce,
          'proof': proof,
        });
      case EncryptedSyncMessage():
        map.addAll({
          'sessionId': message.sessionId,
          'sessionToken': message.sessionToken,
          'issuedAtMs': message.issuedAtMs,
          'nonce': message.nonce,
          'ciphertext': message.ciphertext,
        });
      case SyncProtocolError(:final failure):
        map.addAll({
          'code': failure.code.name,
          if (failure.minimumProtocolVersion != null)
            'minimumProtocolVersion': failure.minimumProtocolVersion,
          if (failure.maximumProtocolVersion != null)
            'maximumProtocolVersion': failure.maximumProtocolVersion,
        });
    }
    return map;
  }

  static SyncProtocolFailure _readFailure(Map<String, Object?> raw) {
    final code = _id(raw, 'code');
    final match = SyncProtocolErrorCode.values.where(
      (item) => item.name == code,
    );
    if (match.isEmpty) throw const FormatException();
    final minimum = raw['minimumProtocolVersion'];
    final maximum = raw['maximumProtocolVersion'];
    if ((minimum != null && minimum is! int) ||
        (maximum != null && maximum is! int)) {
      throw const FormatException();
    }
    return SyncProtocolFailure(
      match.single,
      minimumProtocolVersion: minimum as int?,
      maximumProtocolVersion: maximum as int?,
    );
  }

  static String _id(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  static int _int(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) throw const FormatException();
    return value;
  }

  static String _base64(Map<String, Object?> map, String key) {
    final value = _id(map, key);
    try {
      if (base64Encode(base64Decode(value)) != value) {
        throw const FormatException();
      }
      return value;
    } catch (_) {
      throw const FormatException();
    }
  }
}
