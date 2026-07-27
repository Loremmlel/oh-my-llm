import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';

void main() {
  test('v3 配对记录不再携带分类授权', () {
    final record = SyncPairingRecord(
      peer: const SyncPeerIdentity(id: 'peer', displayName: 'Peer'),
      createdAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );
    expect(record.toJson(), isNot(contains('grantedCategories')));
  });
}
