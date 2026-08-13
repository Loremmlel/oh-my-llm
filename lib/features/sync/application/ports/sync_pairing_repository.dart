import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/session/sync_pairing.dart';

/// 配对 metadata 与 secure secret 的原子边界。
abstract interface class SyncPairingRepository {
  Future<SyncPeerIdentity> localIdentity();

  Future<SyncPeerIdentity> ensureLocalIdentity(List<int> randomBytes);

  Future<SyncPairingRecord?> load(String peerId);

  Future<List<SyncPairingRecord>> loadAll();

  Future<List<int>?> loadSecret(String peerId);

  Future<void> save({
    required SyncPairingRecord record,
    required List<int> secret,
  });

  Future<void> revoke(String peerId);
}

final syncPairingRepositoryProvider = Provider<SyncPairingRepository>((ref) {
  throw StateError('SyncPairingRepository 尚未由应用组合层绑定');
});
