import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/preferences/custom_headers_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
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
import '../helpers/fixtures.dart';

void main() {
  test('loopback v4 配对后通过稳定 group ID 获得结构化 v9 Settings document', () async {
    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final clientStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'client-id', displayName: 'Client'),
    );
    final serverFacade = FakeSettingsSyncFacade();
    serverFacade.exportedDocument = SettingsTransferDocument(
      sections: {
        'presetPrompts': [
          {'id': 'preset-1', 'name': '远端预设'},
        ],
      },
    );
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
    expect(document.toJson()['formatVersion'], 9);
    expect(document.sections.keys, {'presetPrompts'});
    expect(document.sections['presetPrompts'], isA<List<Object?>>());
    expect(
      document.sections.values.every((section) => section is! String),
      isTrue,
    );
    expect(serverFacade.exportedGroups, {const SettingsSyncGroupId('presets')});
    expect(serverFacade.exportCount, 1);
  });

  test('v4 服务端拒绝未确认敏感分组且确认后才导出', () async {
    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final clientStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'client-id', displayName: 'Client'),
    );
    final facade = FakeSettingsSyncFacade();
    final coordinator = SyncServerProtocolCoordinator(
      pairingRepository: serverStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: facade,
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

    final groups = {const SettingsSyncGroupId('providers')};
    await expectLater(
      client.requestSettings(
        server: peer,
        groups: groups,
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
    expect(facade.exportCount, 0);

    final document = await client.requestSettings(
      server: peer,
      groups: groups,
      confirmedSensitive: true,
    );
    expect(document, isA<SettingsTransferDocument>());
    expect(facade.exportCount, 1);
  });

  test('v4 同一服务端会话配对码可供多个客户端重复配对', () async {
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

  test(
    '真实 Provider composition 跨 SQLite 与 SharedPreferences 完成 v4/v9 导出导入',
    () async {
      final serverDatabase = AppDatabase.inMemory();
      final serverPreferences = await _newMockPreferences();
      await memoryPromptRepository.saveAll(serverDatabase, [
        TestFixtures.memoryPrompt(
          id: 'remote-memory',
          name: '远端记忆',
          content: '只应通过 SQLite participant 导入',
        ),
      ]);
      final serverContainer = _createSettingsContainer(
        database: serverDatabase,
        preferences: serverPreferences,
      );
      await serverContainer
          .read(customHeadersProvider.notifier)
          .save(
            const CustomHeadersConfig(
              headers: [
                CustomHeaderEntry(key: 'X-Remote', value: 'remote-secret'),
              ],
            ),
          );

      // 已加载的服务端 controller 保留自己的 provider state；随后重置
      // mock store 只为创建独立的客户端 SharedPreferences 实例。
      expect(serverContainer.read(memoryPromptsProvider), hasLength(1));
      expect(serverContainer.read(customHeadersProvider).headers, hasLength(1));

      final clientDatabase = AppDatabase.inMemory();
      await memoryPromptRepository.saveAll(clientDatabase, [
        TestFixtures.memoryPrompt(
          id: 'local-memory',
          name: '本地记忆',
          content: '导入后仍应保留的本地 sentinel',
        ),
      ]);
      final clientPreferences = await _newMockPreferences();
      final clientContainer = _createSettingsContainer(
        database: clientDatabase,
        preferences: clientPreferences,
      );
      addTearDown(() {
        clientContainer.dispose();
        clientDatabase.close();
        serverContainer.dispose();
        serverDatabase.close();
      });
      await clientContainer
          .read(customHeadersProvider.notifier)
          .save(
            const CustomHeadersConfig(
              headers: [CustomHeaderEntry(key: 'X-Old', value: 'old-value')],
            ),
          );
      expect(
        clientContainer.read(memoryPromptsProvider).map((item) => item.id),
        ['local-memory'],
      );
      expect(
        memoryPromptRepository.loadAll(clientDatabase).map((item) => item.id),
        ['local-memory'],
      );
      expect(
        clientContainer.read(customHeadersProvider),
        const CustomHeadersConfig(
          headers: [CustomHeaderEntry(key: 'X-Old', value: 'old-value')],
        ),
      );

      final serverStore = FakePairingRepository(
        identity: const SyncPeerIdentity(
          id: 'server-id',
          displayName: 'Server',
        ),
      );
      final clientStore = FakePairingRepository(
        identity: const SyncPeerIdentity(
          id: 'client-id',
          displayName: 'Client',
        ),
      );
      final serverCoordinator = SyncServerProtocolCoordinator(
        pairingRepository: serverStore,
        crypto: CryptographySyncCrypto(),
        clock: FakeSyncClock(),
        settingsFacade: serverContainer.read(settingsSyncFacadeProvider),
      );
      final server = SyncHttpServer();
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
      final httpClient = http.Client();
      addTearDown(httpClient.close);
      final client = SyncClientProtocolCoordinator(
        transport: HttpSyncClientTransport(httpClient),
        pairingRepository: clientStore,
        crypto: CryptographySyncCrypto(),
        clock: FakeSyncClock(),
      );
      final groups = {
        const SettingsSyncGroupId('prompts'),
        const SettingsSyncGroupId('network'),
      };

      final pairingCode = await serverCoordinator.generatePairingCode();
      await client.pair(
        server: peer,
        code: pairingCode.toLowerCase(),
        displayName: 'Client',
      );
      await expectLater(
        client.requestSettings(
          server: peer,
          groups: groups,
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

      final document = await client.requestSettings(
        server: peer,
        groups: groups,
        confirmedSensitive: true,
      );
      expect(document.toJson()['formatVersion'], 9);
      expect(document.sections.keys.toSet(), {
        'memoryPrompts',
        'customHeaders',
      });
      expect(document.sections['memoryPrompts'], isA<List<Object?>>());
      expect(document.sections['customHeaders'], isA<Map<String, Object?>>());
      expect(
        document.sections.values.every((section) => section is! String),
        isTrue,
      );

      final prepared = clientContainer
          .read(settingsSyncFacadeProvider)
          .prepareIncoming(document, requestedGroups: groups);
      expect(prepared.containsSensitive, isTrue);
      expect(
        prepared.summaries.map((item) => item.label),
        containsAll(<String>['记忆提示词', '自定义请求头']),
      );
      expect(
        prepared.summaries.every(
          (item) => !item.trailingText.contains('secret'),
        ),
        isTrue,
      );

      final unconfirmed = await prepared.execute(confirmedSensitive: false);
      expect(
        unconfirmed,
        isA<SettingsSyncImportSensitiveConfirmationRequired>(),
      );
      expect(
        clientContainer.read(memoryPromptsProvider).map((item) => item.id),
        ['local-memory'],
      );
      expect(
        memoryPromptRepository.loadAll(clientDatabase).map((item) => item.id),
        ['local-memory'],
      );
      expect(
        clientContainer.read(customHeadersProvider),
        const CustomHeadersConfig(
          headers: [CustomHeaderEntry(key: 'X-Old', value: 'old-value')],
        ),
      );
      expect(
        clientPreferences.getString(customHeadersStorageKey),
        contains('X-Old'),
      );

      final imported = await prepared.execute(confirmedSensitive: true);
      expect(imported, isA<SettingsSyncImportSuccess>());
      expect(
        clientContainer
            .read(memoryPromptsProvider)
            .map((item) => item.id)
            .toSet(),
        {'local-memory', 'remote-memory'},
      );
      expect(
        memoryPromptRepository
            .loadAll(clientDatabase)
            .map((item) => item.id)
            .toSet(),
        {'local-memory', 'remote-memory'},
      );
      expect(
        clientContainer.read(customHeadersProvider),
        const CustomHeadersConfig(
          headers: [CustomHeaderEntry(key: 'X-Remote', value: 'remote-secret')],
        ),
      );
      final persistedHeaders = clientPreferences.getString(
        customHeadersStorageKey,
      );
      expect(persistedHeaders, contains('X-Remote'));
      expect(persistedHeaders, isNot(contains('X-Old')));
    },
  );

  test('真实 Sync response 注入未请求 modelProviders 时在写入前拒绝', () async {
    final clientDatabase = AppDatabase.inMemory();
    await memoryPromptRepository.saveAll(clientDatabase, [
      TestFixtures.memoryPrompt(
        id: 'local-memory',
        name: '本地记忆',
        content: '恶意 response 不得覆盖的 SQLite sentinel',
      ),
    ]);
    final clientPreferences = await _newMockPreferences();
    final clientContainer = _createSettingsContainer(
      database: clientDatabase,
      preferences: clientPreferences,
    );
    addTearDown(() {
      clientContainer.dispose();
      clientDatabase.close();
    });
    await clientContainer
        .read(customHeadersProvider.notifier)
        .save(
          const CustomHeadersConfig(
            headers: [CustomHeaderEntry(key: 'X-Old', value: 'old-value')],
          ),
        );
    const localProvider = LlmProviderConfig(
      id: 'local-provider',
      name: '本地服务商',
      apiUrl: 'https://local.example/v1',
      apiKey: 'local-key',
      apiProtocol: LlmApiProtocol.chatCompletions,
    );
    await clientContainer
        .read(llmProviderConfigsProvider.notifier)
        .upsertProvider(localProvider);

    final memoryIdsBefore = clientContainer
        .read(memoryPromptsProvider)
        .map((item) => item.id)
        .toList();
    final memoryStoreIdsBefore = memoryPromptRepository
        .loadAll(clientDatabase)
        .map((item) => item.id)
        .toList();
    final headersBefore = clientContainer.read(customHeadersProvider);
    final headersRawBefore = clientPreferences.getString(
      customHeadersStorageKey,
    );
    final providersBefore = clientContainer.read(llmProviderConfigsProvider);
    final providersRawBefore = clientPreferences.getString(
      llmModelConfigsStorageKey,
    );

    final serverFacade = FakeSettingsSyncFacade();
    const maliciousProvider = LlmProviderConfig(
      id: 'malicious-provider',
      name: '恶意服务商',
      apiUrl: 'https://malicious.example/v1',
      apiKey: 'malicious-key',
      apiProtocol: LlmApiProtocol.chatCompletions,
    );
    serverFacade.exportedDocument = SettingsTransferDocument(
      sections: {
        'memoryPrompts': [
          TestFixtures.memoryPrompt(
            id: 'remote-memory',
            name: '远端记忆',
            content: '即使允许 prompts，也不应在 section 门禁前写入',
          ).toJson(),
        ],
        'modelProviders': [maliciousProvider.toJson()],
      },
    );

    final serverStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'server-id', displayName: 'Server'),
    );
    final serverCoordinator = SyncServerProtocolCoordinator(
      pairingRepository: serverStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
      settingsFacade: serverFacade,
    );
    final server = SyncHttpServer();
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
    final clientStore = FakePairingRepository(
      identity: const SyncPeerIdentity(id: 'client-id', displayName: 'Client'),
    );
    final httpClient = http.Client();
    addTearDown(httpClient.close);
    final client = SyncClientProtocolCoordinator(
      transport: HttpSyncClientTransport(httpClient),
      pairingRepository: clientStore,
      crypto: CryptographySyncCrypto(),
      clock: FakeSyncClock(),
    );
    final groups = {const SettingsSyncGroupId('prompts')};
    final pairingCode = await serverCoordinator.generatePairingCode();
    await client.pair(
      server: peer,
      code: pairingCode.toLowerCase(),
      displayName: 'Client',
    );

    final document = await client.requestSettings(
      server: peer,
      groups: groups,
      confirmedSensitive: false,
    );
    expect(serverFacade.exportedGroups, groups);
    expect(document.toJson()['formatVersion'], 9);
    expect(document.sections.keys.toSet(), {'memoryPrompts', 'modelProviders'});
    expect(document.sections['memoryPrompts'], isA<List<Object?>>());
    expect(document.sections['modelProviders'], isA<List<Object?>>());
    expect(
      document.sections.values.every((section) => section is! String),
      isTrue,
    );

    expect(
      () => clientContainer
          .read(settingsSyncFacadeProvider)
          .prepareIncoming(document, requestedGroups: groups),
      throwsA(
        isA<SettingsSyncPreparationException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          '同步内容包含未请求的配置项',
        ),
      ),
    );

    expect(
      clientContainer
          .read(memoryPromptsProvider)
          .map((item) => item.id)
          .toList(),
      memoryIdsBefore,
    );
    expect(
      memoryPromptRepository
          .loadAll(clientDatabase)
          .map((item) => item.id)
          .toList(),
      memoryStoreIdsBefore,
    );
    expect(clientContainer.read(customHeadersProvider), headersBefore);
    expect(
      clientPreferences.getString(customHeadersStorageKey),
      headersRawBefore,
    );
    expect(clientContainer.read(llmProviderConfigsProvider), providersBefore);
    expect(
      clientPreferences.getString(llmModelConfigsStorageKey),
      providersRawBefore,
    );
  });
}

Future<SharedPreferences> _newMockPreferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

ProviderContainer _createSettingsContainer({
  required AppDatabase database,
  required SharedPreferences preferences,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...appCompositionOverrides(
        useInMemorySyncSecureStore: true,
        hostPlatform: TargetPlatform.windows,
      ),
    ],
  );
}
