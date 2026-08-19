import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/data/security/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/data/http/http_sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/data/http/sync_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/http/sync_http_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/session/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

import '../features/sync/application/sync_test_fakes.dart';

void main() {
  test('loopback v4 配对后直接获得结构化 Settings document', () async {
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
        groups: {const SettingsSyncGroupId('presets')},
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
    expect(pairingCode, matches(RegExp(r'^[A-Z0-9]{4}$')));
    await client.pair(
      server: peer,
      code: pairingCode.toLowerCase(),
      displayName: 'Client',
    );
    final document = await client.requestSettings(
      server: peer,
      groups: {const SettingsSyncGroupId('presets')},
      confirmedSensitive: false,
    );

    expect(document, isA<SettingsTransferDocument>());
    expect(serverFacade.exportCount, 1);
  });

  test('敏感分类经客户端确认后直接同步', () async {
    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final clientStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'client-id', displayName: 'Client'),
    );
    final coordinator = SyncServerProtocolCoordinator(
      pairingRepository: serverStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: FakeSettingsSyncFacade(),
    );
    final server = SyncHttpServer();
    final port = await server.start(
      handlers: [
        SyncHttpHandler(
          onRequest: (request) async =>
              (await coordinator.handle(request)).message,
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
    final code = await coordinator.generatePairingCode();
    await client.pair(server: peer, code: code, displayName: 'Client');

    final document = await client.requestSettings(
      server: peer,
      groups: {const SettingsSyncGroupId('providers')},
      confirmedSensitive: true,
    );
    expect(document, isA<SettingsTransferDocument>());
  });

  test('同一服务端会话配对码可供多个客户端重复配对', () async {
    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final coordinator = SyncServerProtocolCoordinator(
      pairingRepository: serverStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: FakeSettingsSyncFacade(),
    );
    final server = SyncHttpServer();
    final port = await server.start(
      handlers: [
        SyncHttpHandler(
          onRequest: (request) async =>
              (await coordinator.handle(request)).message,
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
    final code = await coordinator.generatePairingCode();

    for (final clientId in ['client-a', 'client-b']) {
      final client = SyncClientProtocolCoordinator(
        transport: HttpSyncClientTransport(http.Client()),
        pairingRepository: FakePairingRepository(
          identity: SyncPeerIdentity(id: clientId, displayName: clientId),
        ),
        crypto: CryptographySyncCrypto(),
        clock: FakeSyncClock(),
      );
      await client.pair(
        server: peer,
        code: code.toLowerCase(),
        displayName: clientId,
      );
    }

    expect(await coordinator.generatePairingCode(), code);
    expect(await coordinator.pairedPeers(), hasLength(2));
  });
}
