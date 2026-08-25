import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';

import '../../application/ports/sync_pairing_repository.dart';
import '../../domain/models/session/sync_pairing.dart';

/// secure-store 的窄适配器，允许测试替换且避免在 application 暴露插件。
abstract interface class SyncSecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 仅供测试与本机开发注入的内存实现；生产组合必须使用 [FlutterSyncSecureStore]。
final class InMemorySyncSecureStore implements SyncSecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final class FlutterSyncSecureStore implements SyncSecureStore {
  const FlutterSyncSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// metadata 在 SharedPreferences，长期密钥仅在 OS-backed secure storage。
final class SecureSyncPairingRepository implements SyncPairingRepository {
  SecureSyncPairingRepository({
    required SharedPreferences preferences,
    required SyncSecureStore secureStore,
  }) : _preferences = preferences,
       _secureStore = secureStore;

  static const _identityKey = 'sync.v3.identity';
  static const _recordsKey = 'sync.v3.pairings';
  static const _secretPrefix = 'oh-my-llm.sync.v3.secret.';

  final SharedPreferences _preferences;
  final SyncSecureStore _secureStore;

  @override
  Future<SyncPeerIdentity> localIdentity() async {
    final stored = _preferences.getString(_identityKey);
    if (stored != null) {
      final decoded = VersionedJsonStorage.decodeObject(
        rawJson: stored,
        subject: 'sync identity',
      );
      final id = decoded['id'];
      if (id is String && id.isNotEmpty) {
        return SyncPeerIdentity(id: id, displayName: '本机');
      }
    }
    throw StateError('本机 Sync identity 尚未初始化');
  }

  /// 组合层在首次使用时应调用此方法；不会将 identity 派生自时间戳 ID。
  @override
  Future<SyncPeerIdentity> ensureLocalIdentity(List<int> randomBytes) async {
    try {
      return await localIdentity();
    } catch (_) {
      final identity = SyncPeerIdentity(
        id: base64UrlEncode(randomBytes).replaceAll('=', ''),
        displayName: '本机',
      );
      await _preferences.setString(
        _identityKey,
        VersionedJsonStorage.encodeObject(value: {'id': identity.id}),
      );
      return identity;
    }
  }

  @override
  Future<SyncPairingRecord?> load(String peerId) async {
    final records = await loadAll();
    SyncPairingRecord? record;
    for (final item in records) {
      if (item.peer.id == peerId) {
        record = item;
        break;
      }
    }
    if (record == null || await loadSecret(peerId) == null) {
      if (record != null) await revoke(peerId);
      return null;
    }
    return record;
  }

  @override
  Future<List<SyncPairingRecord>> loadAll() async {
    final raw = _preferences.getString(_recordsKey);
    if (raw == null) return const [];
    try {
      final items = VersionedJsonStorage.decodeObjectList(
        rawJson: raw,
        subject: 'sync pairings',
      );
      final records = <SyncPairingRecord>[];
      for (final item in items) {
        final record = SyncPairingRecord.fromJson(
          Map<String, Object?>.from(item),
        );
        if (await loadSecret(record.peer.id) == null) {
          await _deleteMetadata(record.peer.id);
          continue;
        }
        records.add(record);
      }
      return records;
    } catch (_) {
      await _preferences.remove(_recordsKey);
      return const [];
    }
  }

  @override
  Future<List<int>?> loadSecret(String peerId) async {
    try {
      final value = await _secureStore.read(_secretKey(peerId));
      if (value == null) return null;
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save({
    required SyncPairingRecord record,
    required List<int> secret,
  }) async {
    try {
      await _secureStore.write(
        _secretKey(record.peer.id),
        base64Encode(secret),
      );
      final records = await _metadataRecords();
      records.removeWhere((item) => item.peer.id == record.peer.id);
      records.add(record);
      await _saveMetadata(records);
    } catch (error) {
      await _secureStore.delete(_secretKey(record.peer.id));
      await _deleteMetadata(record.peer.id);
      throw StateError('无法安全保存 Sync 配对：$error');
    }
  }

  @override
  Future<void> revoke(String peerId) async {
    try {
      await _secureStore.delete(_secretKey(peerId));
    } finally {
      await _deleteMetadata(peerId);
    }
  }

  String _secretKey(String peerId) => '$_secretPrefix$peerId';

  Future<List<SyncPairingRecord>> _metadataRecords() async {
    final raw = _preferences.getString(_recordsKey);
    if (raw == null) return [];
    final items = VersionedJsonStorage.decodeObjectList(
      rawJson: raw,
      subject: 'sync pairings',
    );
    return items
        .map(
          (item) => SyncPairingRecord.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  Future<void> _saveMetadata(List<SyncPairingRecord> records) =>
      _preferences.setString(
        _recordsKey,
        VersionedJsonStorage.encodeObjectList(
          items: records,
          toJson: (item) => Map<String, dynamic>.from(item.toJson()),
        ),
      );

  Future<void> _deleteMetadata(String peerId) async {
    final records = await _metadataRecords();
    records.removeWhere((item) => item.peer.id == peerId);
    if (records.isEmpty) {
      await _preferences.remove(_recordsKey);
    } else {
      await _saveMetadata(records);
    }
  }
}
