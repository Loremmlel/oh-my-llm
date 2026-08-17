import 'dart:async';
import 'dart:convert';

import 'settings_key_value_store.dart';
import 'versioned_json_storage.dart';

/// 单个设置项的版本化 JSON 存储。
final class VersionedJsonStore<T> {
  const VersionedJsonStore({
    required SettingsKeyValueStore storage,
    required this.key,
    required this.subject,
    required this.fallback,
    required this.fromJson,
    required this.toJson,
  }) : _storage = storage;

  final SettingsKeyValueStore _storage;
  final String key;
  final String subject;
  final T Function() fallback;
  final T Function(JsonMap json) fromJson;
  final JsonMap Function(T value) toJson;

  /// 读取失败时使用安全默认值，避免损坏本地设置阻断启动。
  T load() {
    final rawJson = _storage.getString(key);
    if (rawJson == null || rawJson.isEmpty) return fallback();

    try {
      final decoded = jsonDecode(rawJson);
      // 以是否携带 envelope 标记（version）判断历史裸对象，而非缺失 value：
      // 缺失 value 的截断 envelope（如 {"version":1}）应视为损坏数据回退，
      // 而不是被误判为裸对象重写成损坏值。
      if (decoded is Map && !decoded.containsKey('version')) {
        return fromJson(_canonicalizeLegacyBareObject(decoded, rawJson));
      }
      return fromJson(
        VersionedJsonStorage.decodeObject(rawJson: rawJson, subject: subject),
      );
    } catch (_) {
      return fallback();
    }
  }

  /// 把历史裸对象回写为当前版本化 envelope，避免收紧后旧数据不可读。
  ///
  /// 一次性规范化：两端各启动一次后历史裸对象被重写，本方法即可删除，
  /// [VersionedJsonStorage.decodeObject] 保持仅接受当前 envelope 契约。
  JsonMap _canonicalizeLegacyBareObject(
    Map<dynamic, dynamic> decoded,
    String rawJson,
  ) {
    final json = Map<String, dynamic>.from(decoded);
    // 回写异步落地前若用户已 save() 新值，由 _rewriteCanonical 的串比对放弃，
    // 防止启动期旧值覆盖会话内新值（窗口仅在启动瞬间，但必须守住）。
    unawaited(_rewriteCanonical(json, expectedRaw: rawJson));
    return json;
  }

  Future<void> _rewriteCanonical(
    JsonMap json, {
    required String expectedRaw,
  }) async {
    try {
      // 仅当存储内容仍是本次读取的原始串时才回写：并发 save() 已改写存储则放弃。
      if (_storage.getString(key) != expectedRaw) return;
      await _storage.setString(
        key,
        VersionedJsonStorage.encodeObject(value: json),
      );
    } catch (_) {
      // 尽力而为：回写失败不影响本次读取，下次启动会重试。
    }
  }

  /// 仅在底层写入确认成功后完成。
  Future<void> save(T value) async {
    final didPersist = await _storage.setString(
      key,
      VersionedJsonStorage.encodeObject(value: toJson(value)),
    );
    if (!didPersist) {
      throw StateError('Failed to persist $subject.');
    }
  }
}
