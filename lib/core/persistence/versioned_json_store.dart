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
      return fromJson(
        VersionedJsonStorage.decodeObject(rawJson: rawJson, subject: subject),
      );
    } catch (_) {
      return fallback();
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
