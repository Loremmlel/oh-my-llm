import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';
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

  @override
  Future<void> updateGrants(String peerId, Set<SyncCategory> grants) async {
    final record = records[peerId]!;
    records[peerId] = record.copyWith(grantedCategories: grants);
  }
}

final class FakeSettingsSyncFacade implements SettingsSyncFacade {
  var exportCount = 0;
  @override
  SettingsExportData deduplicateIncoming(SettingsExportData data) => data;
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
