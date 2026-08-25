import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late SettingsSyncFacade facade;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(() {
      container.dispose();
      database.close();
    });
    facade = RiverpodSettingsSyncFacade(
      catalog: container.read(settingsTransferCatalogProvider),
      coordinator: container.read(settingsTransferCoordinatorProvider),
    );
  });

  test('production facade 投影六个有序分组并聚合敏感性', () {
    expect(facade.availableGroups.map((group) => group.id.value), [
      'providers',
      'presets',
      'prompts',
      'network',
      'outputProcessing',
      'other',
    ]);
    expect(
      facade.availableGroups
          .firstWhere((group) => group.id.value == 'providers')
          .sensitivity,
      SettingsSyncSensitivity.credentialBearing,
    );
    expect(
      facade.availableGroups
          .firstWhere((group) => group.id.value == 'network')
          .sensitivity,
      SettingsSyncSensitivity.credentialBearing,
    );
    expect(
      facade.availableGroups
          .firstWhere((group) => group.id.value == 'other')
          .sensitivity,
      SettingsSyncSensitivity.standard,
    );
  });

  test('新增 participant 自动进入导出、摘要和执行，不需要 facade 分支', () async {
    var localValue = 'local';
    var writeCount = 0;
    final participant = _StringParticipant(
      readLocal: () => localValue,
      write: (value) async {
        writeCount++;
        localValue = value;
      },
    );
    final catalog = SettingsTransferCatalog([
      SettingsTransferParticipantBox.erase(participant),
    ]);
    final adapter = RiverpodSettingsSyncFacade(
      catalog: catalog,
      coordinator: SettingsTransferCoordinator(catalog: catalog),
    );

    final exported = adapter.exportGroups({
      const SettingsSyncGroupId('providers'),
    });
    expect(exported.sections, {'extraSetting': 'local'});

    final prepared = adapter.prepareIncoming(
      SettingsTransferDocument(sections: {'extraSetting': 'incoming'}),
      requestedGroups: {const SettingsSyncGroupId('providers')},
    );
    expect(prepared.summaries, [
      const SettingsSyncSummaryItem(label: '额外设置', trailingText: '替换'),
    ]);
    expect(prepared.containsSensitive, isFalse);

    final result = await prepared.execute(confirmedSensitive: false);
    expect(result, isA<SettingsSyncImportSuccess>());
    expect(localValue, 'incoming');
    expect(writeCount, 1);
  });

  test('未知请求分组在 coordinator 之前被拒绝', () {
    expect(
      () => facade.exportGroups({const SettingsSyncGroupId('unknownGroup')}),
      throwsA(isA<SettingsSyncPreparationException>()),
    );
  });

  test('已知 section 不在请求分组内时在任何写入前被拒绝', () {
    final document = SettingsTransferDocument(
      sections: {'modelProviders': <Object?>[]},
    );

    expect(
      () => facade.prepareIncoming(
        document,
        requestedGroups: {const SettingsSyncGroupId('prompts')},
      ),
      throwsA(isA<SettingsSyncPreparationException>()),
    );
  });

  test('本地媒体密度不进入 catalog 投影或设置文档', () async {
    await preferences.setString(mediaGridDensityStorageKey, 'comfortable');
    final document = facade.exportGroups({const SettingsSyncGroupId('other')});
    expect(document.sections, isNot(contains(mediaGridDensityStorageKey)));
    expect(document.sections, isNot(contains('grid_density')));
  });
}

final class _StringParticipant extends ReplacingValueParticipant<String> {
  _StringParticipant({required this._readLocal, required this._write})
    : super(
        key: const SettingsTransferKey('extraSetting'),
        group: SettingsTransferGroup.providers,
        label: '额外设置',
        order: 99,
        sensitivity: SettingsTransferSensitivity.standard,
      );

  final String Function() _readLocal;
  final Future<void> Function(String value) _write;

  @override
  String readLocal() => _readLocal();

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? payload) {
    if (payload is! String) throw const FormatException();
    return payload;
  }

  @override
  bool isEquivalent(String existing, String incoming) => existing == incoming;

  @override
  Future<void> applyImport(String value) => _write(value);
}
