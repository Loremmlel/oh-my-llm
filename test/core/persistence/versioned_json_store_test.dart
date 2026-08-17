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
  test('历史裸对象不再被接受，读取回退到安全默认值', () {
    final storage = _FakeSettingsKeyValueStore(
      stringValues: {'settings.font_size': '{"bodyFontSize":18}'},
    );
    final store = _createStore(storage);

    expect(store.load(), const FontSizeSettings());
  });

  test('保存为当前版本化 envelope', () async {
    final storage = _FakeSettingsKeyValueStore();
    final store = _createStore(storage);

    await store.save(const FontSizeSettings(bodyFontSize: 20));

    expect(jsonDecode(storage.stringValues['settings.font_size']!), {
      'version': VersionedJsonStorage.currentSchemaVersion,
      'value': {'bodyFontSize': 20},
    });
  });

  test('含版本标记但缺失 value 的截断 envelope 按损坏回退且不重写', () async {
    final storage = _FakeSettingsKeyValueStore(
      stringValues: {'settings.font_size': '{"version":1}'},
    );
    final store = _createStore(storage);

    expect(store.load(), const FontSizeSettings());
    await pumpEventQueue();

    // 截断 envelope 不得被改写成损坏值，存储保持原样。
    expect(storage.stringValues['settings.font_size'], '{"version":1}');
  });

  test('returns fallback for malformed and unsupported stored values', () {
    for (final rawJson in [
      '{bad json}',
      '{"version":${VersionedJsonStorage.currentSchemaVersion + 1},"value":{"bodyFontSize":20}}',
      '{"version":"1","value":{"bodyFontSize":20}}',
    ]) {
      final store = _createStore(
        _FakeSettingsKeyValueStore(
          stringValues: {'settings.font_size': rawJson},
        ),
      );

      expect(store.load(), const FontSizeSettings());
    }
  });

  test(
    'save completes with an error when preferences rejects the write',
    () async {
      final store = _createStore(
        _FakeSettingsKeyValueStore(nextWriteResult: false),
      );

      await expectLater(
        store.save(const FontSizeSettings(bodyFontSize: 20)),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('save propagates storage errors', () async {
    final error = Exception('disk unavailable');
    final store = _createStore(_FakeSettingsKeyValueStore(writeError: error));

    await expectLater(
      store.save(const FontSizeSettings(bodyFontSize: 20)),
      throwsA(same(error)),
    );
  });
}
