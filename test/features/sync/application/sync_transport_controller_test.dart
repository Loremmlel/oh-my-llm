import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_message.dart';

import 'sync_test_fakes.dart';

void main() {
  test('匿名请求在 facade 之前被拒绝', () async {
    final facade = FakeSettingsSyncFacade();
    final coordinator = SyncServerProtocolCoordinator(
      pairingRepository: FakePairingRepository(),
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: facade,
    );

    final result = await coordinator.handle(
      const EncryptedSyncRequest(
        requestId: 'request',
        sessionId: 'session',
        sessionToken: 'dG9rZW4=',
        issuedAtMs: 0,
        nonce: 'MTIzNDU2Nzg5MDEy',
        ciphertext: 'YQ==',
      ),
    );

    expect(result.message, isA<SyncProtocolError>());
    expect(
      (result.message as SyncProtocolError).failure.code,
      SyncProtocolErrorCode.sessionInvalid,
    );
    expect(facade.exportCount, 0);
  });
}
