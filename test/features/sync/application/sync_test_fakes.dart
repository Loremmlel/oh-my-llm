import 'dart:async';

import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_protocol.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/session/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

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
  SettingsTransferDocument requestResult = SettingsTransferDocument(
    sections: const {},
  );
  Completer<void>? pairGate;
  Completer<void>? requestGate;
  String? pairedCode;
  bool? requestedSensitiveConfirmation;
  Set<SettingsSyncGroupId>? requestedGroups;
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
  Future<SettingsTransferDocument> requestSettings({
    required DiscoveredServer server,
    Set<SettingsSyncGroupId>? groups,
    Object? categories,
    required bool confirmedSensitive,
  }) async {
    if (requestGate != null) await requestGate!.future;
    requestedGroups = groups;
    requestedCategories = categories is Set<SyncCategory> ? categories : null;
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
  FakeSettingsSyncFacade({List<SettingsSyncGroupDescriptor>? availableGroups})
    : availableGroups = List.unmodifiable(availableGroups ?? _defaultGroups);

  @override
  final List<SettingsSyncGroupDescriptor> availableGroups;

  var exportCount = 0;
  Set<SettingsSyncGroupId>? exportedGroups;
  Set<SettingsSyncGroupId>? requestedGroups;
  SettingsTransferDocument exportedDocument = SettingsTransferDocument(
    sections: const {},
  );
  SettingsSyncPreparedImport? preparedImport;
  Object? preparationError;

  @override
  SettingsTransferDocument exportGroups(Set<SettingsSyncGroupId> groups) {
    exportCount++;
    exportedGroups = Set.unmodifiable(groups);
    return exportedDocument;
  }

  @override
  SettingsSyncPreparedImport prepareIncoming(
    SettingsTransferDocument document, {
    required Set<SettingsSyncGroupId> requestedGroups,
  }) {
    this.requestedGroups = Set.unmodifiable(requestedGroups);
    if (preparationError != null) throw preparationError!;
    return preparedImport ?? ScriptedSettingsSyncPreparedImport();
  }
}

final class ScriptedSettingsSyncPreparedImport
    implements SettingsSyncPreparedImport {
  ScriptedSettingsSyncPreparedImport({
    this.summaries = const [],
    this.containsSensitive = false,
    this.executeResult = const SettingsSyncImportSuccess(),
  });

  @override
  final List<SettingsSyncSummaryItem> summaries;

  @override
  final bool containsSensitive;

  SettingsSyncImportExecutionResult executeResult;
  bool? requestedSensitiveConfirmation;

  @override
  Future<SettingsSyncImportExecutionResult> execute({
    required bool confirmedSensitive,
  }) async {
    requestedSensitiveConfirmation = confirmedSensitive;
    return executeResult;
  }
}

const _defaultGroups = [
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('providers'),
    label: '服务商',
    order: 0,
    sensitivity: SettingsSyncSensitivity.credentialBearing,
  ),
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('presets'),
    label: '预设',
    order: 1,
    sensitivity: SettingsSyncSensitivity.standard,
  ),
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('prompts'),
    label: '提示词',
    order: 2,
    sensitivity: SettingsSyncSensitivity.standard,
  ),
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('network'),
    label: '网络',
    order: 3,
    sensitivity: SettingsSyncSensitivity.credentialBearing,
  ),
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('outputProcessing'),
    label: '输出处理',
    order: 4,
    sensitivity: SettingsSyncSensitivity.standard,
  ),
  SettingsSyncGroupDescriptor(
    id: SettingsSyncGroupId('other'),
    label: '其它',
    order: 5,
    sensitivity: SettingsSyncSensitivity.standard,
  ),
];
