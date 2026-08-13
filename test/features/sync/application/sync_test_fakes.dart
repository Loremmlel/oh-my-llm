import 'dart:async';

import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_protocol.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

final class FakeSyncClock implements SyncClock {
  FakeSyncClock([DateTime? now]) : value = now ?? DateTime(2026, 1, 1);
  DateTime value;
  @override
  DateTime now() => value;
}

final class FakePairingRepository implements SyncPairingRepository {
  FakePairingRepository({
    this.identity = const SyncPeerIdentity(id: 'server', displayName: 'Server'),
  });
  final SyncPeerIdentity identity;
  final Map<String, SyncPairingRecord> records = {};
  final Map<String, List<int>> secrets = {};

  @override
  Future<SyncPeerIdentity> ensureLocalIdentity(List<int> randomBytes) async =>
      identity;
  @override
  Future<SyncPeerIdentity> localIdentity() async => identity;
  @override
  Future<SyncPairingRecord?> load(String peerId) async => records[peerId];
  @override
  Future<List<SyncPairingRecord>> loadAll() async => records.values.toList();
  @override
  Future<List<int>?> loadSecret(String peerId) async => secrets[peerId];
  @override
  Future<void> revoke(String peerId) async {
    records.remove(peerId);
    secrets.remove(peerId);
  }

  @override
  Future<void> save({
    required SyncPairingRecord record,
    required List<int> secret,
  }) async {
    records[record.peer.id] = record;
    secrets[record.peer.id] = secret;
  }
}

/// 可手动推送发现事件与关闭流的传输 fake，用于服务端断开检测用例。
///
/// 非广播单订阅流：一个用例只调用一次 `startDiscovery`。
final class FakeSyncClientTransport implements SyncClientTransport {
  final StreamController<DiscoveredServer> _controller =
      StreamController<DiscoveredServer>();

  @override
  Stream<DiscoveredServer> discoverServers() => _controller.stream;

  void add(DiscoveredServer server) => _controller.add(server);

  void addError(Object error) => _controller.addError(error);

  Future<void> close() async {
    if (_controller.isClosed) return;
    await _controller.close();
  }

  @override
  Future<SyncProtocolMessage> send({
    required DiscoveredServer server,
    required SyncProtocolMessage request,
  }) {
    throw UnimplementedError('断开检测用例不涉及 HTTP 发送');
  }
}

/// 可脚本化编排协议结果的 fake：配对、请求、撤销与清会话全部记录调用，
/// 且可用 [pairGate] / [requestGate] 挂起等待，模拟晚到完成竞态。
final class ScriptedSyncClientProtocol implements SyncClientProtocol {
  bool paired = false;
  Object? pairError;
  Object? requestError;
  SettingsExportData requestResult = const SettingsExportData(
    modelProviders: [],
    memoryPrompts: [],
    presetPrompts: [],
    templatePrompts: [],
    fixedPromptSequences: [],
  );
  Completer<void>? pairGate;
  Completer<void>? requestGate;
  String? pairedCode;
  bool? requestedSensitiveConfirmation;
  Set<SyncCategory>? requestedCategories;
  int forgetCount = 0;
  int clearSessionsCount = 0;
  int isPairedCount = 0;

  @override
  Future<bool> isPaired(DiscoveredServer server) async {
    isPairedCount++;
    return paired;
  }

  @override
  Future<void> pair({
    required DiscoveredServer server,
    required String code,
    required String displayName,
  }) async {
    if (pairGate != null) await pairGate!.future;
    pairedCode = code;
    if (pairError != null) throw pairError!;
    paired = true;
  }

  @override
  Future<SettingsExportData> requestSettings({
    required DiscoveredServer server,
    required Set<SyncCategory> categories,
    required bool confirmedSensitive,
  }) async {
    if (requestGate != null) await requestGate!.future;
    requestedCategories = categories;
    requestedSensitiveConfirmation = confirmedSensitive;
    if (requestError != null) throw requestError!;
    return requestResult;
  }

  @override
  Future<void> forgetPairing(DiscoveredServer server) async {
    forgetCount++;
    paired = false;
  }

  @override
  void clearSessions() {
    clearSessionsCount++;
  }
}

final class FakeSettingsSyncFacade implements SettingsSyncFacade {
  var exportCount = 0;
  SettingsExportData? deduplicatedResult;
  @override
  SettingsExportData deduplicateIncoming(SettingsExportData data) =>
      deduplicatedResult ?? data;
  @override
  SettingsExportData exportSelected(SettingsSyncSelection selection) {
    exportCount++;
    return const SettingsExportData(
      modelProviders: [],
      memoryPrompts: [],
      presetPrompts: [],
      templatePrompts: [],
      fixedPromptSequences: [],
    );
  }

  @override
  Future<bool> importDeduplicated(SettingsExportData data) async => true;
}
