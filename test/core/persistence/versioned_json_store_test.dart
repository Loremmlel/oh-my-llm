import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';

final class _FakeSettingsKeyValueStore implements SettingsKeyValueStore {
  _FakeSettingsKeyValueStore({
    Map<String, String>? stringValues,
    this.nextWriteResult = true,
    this.writeError,
  }) : stringValues = {...?stringValues};

  final Map<String, String> stringValues;
  final Map<String, int> intValues = {};
  bool nextWriteResult;
  Object? writeError;

  @override
  String? getString(String key) => stringValues[key];

  @override
  int? getInt(String key) => intValues[key];

  @override
  Future<bool> setInt(String key, int value) async {
    intValues[key] = value;
    return nextWriteResult;
  }

  @override
  Future<bool> setString(String key, String value) async {
    final error = writeError;
    if (error != null) throw error;
    if (nextWriteResult) stringValues[key] = value;
    return nextWriteResult;
  }
}

VersionedJsonStore<FontSizeSettings> _createStore(
  _FakeSettingsKeyValueStore storage,
) {
  return VersionedJsonStore<FontSizeSettings>(
    storage: storage,
    key: 'settings.font_size',
    subject: 'font size settings',
    fallback: () => const FontSizeSettings(),
    fromJson: FontSizeSettings.fromJson,
    toJson: (value) => value.toJson(),
  );
}

void main() {
  test('保存当前版本化 envelope 后可重新读取', () async {
    final storage = _FakeSettingsKeyValueStore();
    final store = _createStore(storage);

    await store.save(const FontSizeSettings(bodyFontSize: 20));

    expect(jsonDecode(storage.stringValues['settings.font_size']!), {
      'version': VersionedJsonStorage.currentSchemaVersion,
      'value': {'bodyFontSize': 20},
    });
    expect(store.load(), const FontSizeSettings(bodyFontSize: 20));
  });

  test('损坏、裸对象和不支持的版本回退到默认值且不重写存储', () {
    for (final rawJson in [
      '{"bodyFontSize":18}',
      '{"version":1}',
      '{bad json}',
      '{"version":${VersionedJsonStorage.currentSchemaVersion + 1},"value":{"bodyFontSize":20}}',
      '{"version":"1","value":{"bodyFontSize":20}}',
    ]) {
      final storage = _FakeSettingsKeyValueStore(
        stringValues: {'settings.font_size': rawJson},
      );
      expect(
        _createStore(storage).load(),
        const FontSizeSettings(),
        reason: rawJson,
      );
      expect(storage.stringValues['settings.font_size'], rawJson);
    }
  });

  test('存储拒绝写入时保存失败', () async {
    final store = _createStore(
      _FakeSettingsKeyValueStore(nextWriteResult: false),
    );

    await expectLater(
      store.save(const FontSizeSettings(bodyFontSize: 20)),
      throwsA(isA<StateError>()),
    );
  });

  test('保存传播存储异常', () async {
    final error = Exception('disk unavailable');
    final store = _createStore(_FakeSettingsKeyValueStore(writeError: error));

    await expectLater(
      store.save(const FontSizeSettings(bodyFontSize: 20)),
      throwsA(same(error)),
    );
  });
}
