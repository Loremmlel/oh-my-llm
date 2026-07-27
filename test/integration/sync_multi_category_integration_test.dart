import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

import '../features/sync/application/sync_test_fakes.dart';

void main() {
  test('credential-bearing category 需要服务端明确确认后才可 grant', () async {
    final store = FakePairingRepository();
    await store.save(
      record: SyncPairingRecord(
        peer: const SyncPeerIdentity(id: 'peer', displayName: 'Peer'),
        grantedCategories: const {},
        createdAt: DateTime(2026),
        lastUsedAt: DateTime(2026),
      ),
      secret: const [1],
    );
    final coordinator = SyncServerProtocolCoordinator(
      pairingRepository: store,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: FakeSettingsSyncFacade(),
    );

    await expectLater(
      coordinator.grant(
        peerId: 'peer',
        categories: {SyncCategory.providers},
        confirmedSensitive: false,
      ),
      throwsA(
        isA<SyncProtocolFailure>().having(
          (failure) => failure.code,
          'code',
          SyncProtocolErrorCode.sensitiveConfirmationRequired,
        ),
      ),
    );
    await coordinator.grant(
      peerId: 'peer',
      categories: {SyncCategory.providers, SyncCategory.prompts},
      confirmedSensitive: true,
    );

    expect((await store.load('peer'))!.grantedCategories, {
      SyncCategory.providers,
      SyncCategory.prompts,
    });
  });
}
