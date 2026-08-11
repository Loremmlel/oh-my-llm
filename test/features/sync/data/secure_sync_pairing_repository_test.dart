import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/data/secure_sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_pairing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录写入/删除、可注入读写失败的 secure store 替身，用于验证隔离与清理契约。
final class _RecordingSecureStore implements SyncSecureStore {
  final values = <String, String>{};
  final writes = <String>[];
  final deletes = <String>[];
  Object? writeError;
  Object? readError;

  @override
  Future<String?> read(String key) async {
    if (readError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    if (writeError case final error?) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    values.remove(key);
  }
}

SyncPairingRecord _record(String peerId) => SyncPairingRecord(
  peer: SyncPeerIdentity(id: peerId, displayName: '远端-$peerId'),
  createdAt: DateTime(2026, 1, 1),
  lastUsedAt: DateTime(2026, 1, 2),
);

void main() {
  late SharedPreferences preferences;
  late _RecordingSecureStore secureStore;
  late SecureSyncPairingRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secureStore = _RecordingSecureStore();
    repository = SecureSyncPairingRepository(
      preferences: preferences,
      secureStore: secureStore,
    );
  });

  test('ensureLocalIdentity 首次生成后保持稳定', () async {
    final first = await repository.ensureLocalIdentity([1, 2, 3, 4]);
    final second = await repository.ensureLocalIdentity([9, 9, 9, 9]);

    expect(first.id, 'AQIDBA');
    expect(second, first);
    expect(await repository.localIdentity(), first);
  });

  test('save 仅把 secret 写入 secure store 并可完整读取', () async {
    final record = _record('peer-a');
    const secret = [1, 2, 3, 4];

    await repository.save(record: record, secret: secret);

    expect(await repository.load('peer-a'), record);
    expect(await repository.loadAll(), [record]);
    expect(await repository.loadSecret('peer-a'), secret);
    expect(secureStore.writes, hasLength(1));
    expect(
      preferences.getKeys().map(preferences.get).join('\n'),
      isNot(contains(base64Encode(secret))),
    );
  });

  test('revoke 只移除目标 peer 的 secret 与 metadata', () async {
    await repository.save(record: _record('peer-a'), secret: [1]);
    await repository.save(record: _record('peer-b'), secret: [2]);

    await repository.revoke('peer-a');

    expect(await repository.load('peer-a'), isNull);
    expect(await repository.load('peer-b'), _record('peer-b'));
    expect(await repository.loadSecret('peer-a'), isNull);
    expect(await repository.loadSecret('peer-b'), [2]);
  });

  test('secret 缺失时 load 拒绝记录并清理孤立 metadata', () async {
    final record = _record('peer-a');
    await repository.save(record: record, secret: [1, 2, 3]);
    secureStore.values.clear();

    expect(await repository.load('peer-a'), isNull);
    expect(await repository.loadAll(), isEmpty);
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });

  test('secret base64 损坏时 loadAll 清理对应 metadata', () async {
    await repository.save(record: _record('peer-a'), secret: [1, 2, 3]);
    final secretKey = secureStore.writes.single;
    secureStore.values[secretKey] = '%%%';

    expect(await repository.loadAll(), isEmpty);
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });

  test('secure store 写入失败时清理目标并抛稳定 StateError', () async {
    secureStore.writeError = StateError('secure write failed');

    await expectLater(
      repository.save(record: _record('peer-a'), secret: [1]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('无法安全保存 Sync 配对'),
        ),
      ),
    );
    expect(secureStore.deletes, hasLength(1));
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });

  test('pairings 持久化元数据损坏为非法 JSON 时 loadAll 返回空并移除键', () async {
    await preferences.setString('sync.v3.pairings', 'not-a-json{{{');

    expect(await repository.loadAll(), isEmpty);
    expect(preferences.getString('sync.v3.pairings'), isNull);
  });
}
