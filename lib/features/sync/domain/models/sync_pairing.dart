import 'dart:convert';

import 'package:equatable/equatable.dart';

/// 本安装或远端安装的稳定身份。显示名不是安全身份的一部分。
final class SyncPeerIdentity extends Equatable {
  const SyncPeerIdentity({required this.id, required this.displayName});

  final String id;
  final String displayName;

  @override
  List<Object?> get props => [id, displayName];
}

/// 长期配对记录的非秘密投影。shared secret 始终由 secure store 单独保存。
final class SyncPairingRecord extends Equatable {
  const SyncPairingRecord({
    required this.peer,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final SyncPeerIdentity peer;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  SyncPairingRecord copyWith({DateTime? lastUsedAt}) => SyncPairingRecord(
    peer: peer,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'id': peer.id,
    'displayName': peer.displayName,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'lastUsedAtMs': lastUsedAt.millisecondsSinceEpoch,
  };

  static SyncPairingRecord fromJson(Map<String, Object?> raw) {
    final id = raw['id'];
    final displayName = raw['displayName'];
    final createdAt = raw['createdAtMs'];
    final lastUsedAt = raw['lastUsedAtMs'];
    if (id is! String ||
        id.isEmpty ||
        displayName is! String ||
        displayName.isEmpty ||
        createdAt is! int ||
        lastUsedAt is! int) {
      throw const FormatException('配对记录格式无效');
    }
    return SyncPairingRecord(
      peer: SyncPeerIdentity(id: id, displayName: displayName),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(lastUsedAt),
    );
  }

  @override
  List<Object?> get props => [peer, createdAt, lastUsedAt];
}

/// 等待服务端本地确认的分类授权请求，仅保留非秘密元数据。
/// pairing proof 和 pairing secret 所依赖的固定 transcript。
final class SyncPairingTranscript {
  const SyncPairingTranscript({
    required this.serverIdentity,
    required this.pairingId,
    required this.challengeNonce,
    required this.clientIdentity,
    required this.clientNonce,
  });

  final String serverIdentity;
  final String pairingId;
  final String challengeNonce;
  final String clientIdentity;
  final String clientNonce;

  List<int> get canonicalBytes => utf8.encode(
    jsonEncode({
      'protocolVersion': 3,
      'serverIdentity': serverIdentity,
      'pairingId': pairingId,
      'challengeNonce': challengeNonce,
      'clientIdentity': clientIdentity,
      'clientNonce': clientNonce,
    }),
  );
}
