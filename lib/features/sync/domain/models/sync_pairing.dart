import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'sync_types.dart';

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
  SyncPairingRecord({
    required this.peer,
    required Set<SyncCategory> grantedCategories,
    required this.createdAt,
    required this.lastUsedAt,
  }) : grantedCategories = Set.unmodifiable(grantedCategories);

  final SyncPeerIdentity peer;
  final Set<SyncCategory> grantedCategories;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  SyncPairingRecord copyWith({
    Set<SyncCategory>? grantedCategories,
    DateTime? lastUsedAt,
  }) => SyncPairingRecord(
    peer: peer,
    grantedCategories: grantedCategories ?? this.grantedCategories,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'id': peer.id,
    'displayName': peer.displayName,
    'grantedCategories': grantedCategories
        .map((item) => item.payloadKey)
        .toList(),
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'lastUsedAtMs': lastUsedAt.millisecondsSinceEpoch,
  };

  static SyncPairingRecord fromJson(Map<String, Object?> raw) {
    final id = raw['id'];
    final displayName = raw['displayName'];
    final categories = raw['grantedCategories'];
    final createdAt = raw['createdAtMs'];
    final lastUsedAt = raw['lastUsedAtMs'];
    if (id is! String ||
        id.isEmpty ||
        displayName is! String ||
        displayName.isEmpty ||
        categories is! List ||
        createdAt is! int ||
        lastUsedAt is! int) {
      throw const FormatException('配对记录格式无效');
    }
    final grants = <SyncCategory>{};
    for (final item in categories) {
      if (item is! String) throw const FormatException('配对分类格式无效');
      final matches = SyncCategory.values.where(
        (value) => value.payloadKey == item,
      );
      if (matches.isEmpty || !grants.add(matches.single)) {
        throw const FormatException('配对分类无效');
      }
    }
    return SyncPairingRecord(
      peer: SyncPeerIdentity(id: id, displayName: displayName),
      grantedCategories: grants,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(lastUsedAt),
    );
  }

  @override
  List<Object?> get props => [
    peer,
    grantedCategories.map((item) => item.index).toList()..sort(),
    createdAt,
    lastUsedAt,
  ];
}

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
      'protocolVersion': 2,
      'serverIdentity': serverIdentity,
      'pairingId': pairingId,
      'challengeNonce': challengeNonce,
      'clientIdentity': clientIdentity,
      'clientNonce': clientNonce,
    }),
  );
}
