import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/data/http_sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

import '../features/sync/application/sync_test_fakes.dart';

void main() {
  test('loopback v2 已配对、授权 session 才能获得结构化 Settings snapshot', () async {
    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final clientStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'client-id', displayName: 'Client'),
    );
    final serverFacade = FakeSettingsSyncFacade();
    final server = SyncHttpServer();
    final serverCoordinator = SyncServerProtocolCoordinator(
      pairingRepository: serverStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: serverFacade,
    );
    final port = await server.start(
      handlers: [
        SyncHttpHandler(
          onRequest: (request) async =>
              (await serverCoordinator.handle(request)).message,
        ),
      ],
    );
    addTearDown(server.stop);

    final peer = DiscoveredServer(
      deviceName: 'Server',
      ip: InternetAddress.loopbackIPv4.address,
      httpPort: port,
      serverId: 'server-id',
      protocolRange: SyncProtocolRange.local,
    );
    final client = SyncClientProtocolCoordinator(
      transport: HttpSyncClientTransport(http.Client()),
      pairingRepository: clientStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
    );

    await expectLater(
      client.requestSettings(
        server: peer,
        categories: {SyncCategory.presets},
        confirmedSensitive: false,
      ),
      throwsA(
        isA<SyncProtocolFailure>().having(
          (failure) => failure.code,
          'code',
          SyncProtocolErrorCode.pairingRequired,
        ),
      ),
    );
    expect(serverFacade.exportCount, 0);

    final pairingCode = await serverCoordinator.generatePairingCode();
    await client.pair(server: peer, code: pairingCode, displayName: 'Client');
    await expectLater(
      client.requestSettings(
        server: peer,
        categories: {SyncCategory.presets},
        confirmedSensitive: false,
      ),
      throwsA(
        isA<SyncProtocolFailure>().having(
          (failure) => failure.code,
          'code',
          SyncProtocolErrorCode.authorizationRequired,
        ),
      ),
    );
    expect(serverFacade.exportCount, 0);

    await serverCoordinator.grant(
      peerId: 'client-id',
      categories: {SyncCategory.presets},
      confirmedSensitive: false,
    );
    final snapshot = await client.requestSettings(
      server: peer,
      categories: {SyncCategory.presets},
      confirmedSensitive: false,
    );

    expect(snapshot, isA<SettingsExportData>());
    expect(serverFacade.exportCount, 1);
  });
}
