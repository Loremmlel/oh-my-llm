import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

import 'sync_test_fakes.dart';

/// 测试用子类：覆盖 build() 以注入预置的 prepared import。
class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this._seed);

  final SyncClientState _seed;

  @override
  SyncClientState build() => _seed;
}

void main() {
  ProviderContainer buildContainer({
    required SyncClientState seed,
    required FakeSettingsSyncFacade facade,
  }) {
    final container = ProviderContainer(
      overrides: [
        settingsSyncFacadeProvider.overrideWithValue(facade),
        syncClientControllerProvider.overrideWith(
          () => _SeededSyncClientController(seed),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('执行会把导入时敏感确认独立转发给 prepared import', () async {
    final prepared = ScriptedSettingsSyncPreparedImport(
      containsSensitive: true,
      executeResult: const SettingsSyncImportSensitiveConfirmationRequired(),
    );
    final facade = FakeSettingsSyncFacade()..preparedImport = prepared;
    final container = buildContainer(
      facade: facade,
      seed: SyncClientState(
        phase: SyncPhase.received,
        preparedImport: prepared,
      ),
    );

    final result = await container
        .read(syncClientControllerProvider.notifier)
        .executePreparedImport(confirmedSensitive: false);

    expect(result, isA<SettingsSyncImportSensitiveConfirmationRequired>());
    expect(prepared.requestedSensitiveConfirmation, isFalse);
    expect(
      container.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );
  });

  test('成功执行后进入 imported', () async {
    final prepared = ScriptedSettingsSyncPreparedImport();
    final facade = FakeSettingsSyncFacade()..preparedImport = prepared;
    final container = buildContainer(
      facade: facade,
      seed: SyncClientState(
        phase: SyncPhase.received,
        preparedImport: prepared,
      ),
    );

    final result = await container
        .read(syncClientControllerProvider.notifier)
        .executePreparedImport(confirmedSensitive: true);

    expect(result, isA<SettingsSyncImportSuccess>());
    expect(
      container.read(syncClientControllerProvider).phase,
      SyncPhase.imported,
    );
  });

  test('stale 结果替换 prepared import 并保持 received', () async {
    final refreshed = ScriptedSettingsSyncPreparedImport(
      summaries: const [
        SettingsSyncSummaryItem(label: '刷新项', trailingText: '替换'),
      ],
    );
    final prepared = ScriptedSettingsSyncPreparedImport(
      executeResult: SettingsSyncImportStalePreview(refreshed),
    );
    final facade = FakeSettingsSyncFacade()..preparedImport = prepared;
    final container = buildContainer(
      facade: facade,
      seed: SyncClientState(
        phase: SyncPhase.received,
        preparedImport: prepared,
      ),
    );

    final result = await container
        .read(syncClientControllerProvider.notifier)
        .executePreparedImport(confirmedSensitive: true);

    expect(result, isA<SettingsSyncImportStalePreview>());
    expect(
      container.read(syncClientControllerProvider).preparedImport,
      same(refreshed),
    );
    expect(
      container.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );
  });

  test('partial failure 返回安全结果并保留 prepared import 供界面处理', () async {
    final prepared = ScriptedSettingsSyncPreparedImport(
      executeResult: const SettingsSyncImportPartialFailure(
        completed: [SettingsSyncSummaryItem(label: '已完成', trailingText: '替换')],
        failedLabel: '失败项',
        notAttempted: [
          SettingsSyncSummaryItem(label: '未执行', trailingText: '新增 1 项'),
        ],
        safeReason: '写入未完成，请检查本地存储后重试',
      ),
    );
    final facade = FakeSettingsSyncFacade()..preparedImport = prepared;
    final container = buildContainer(
      facade: facade,
      seed: SyncClientState(
        phase: SyncPhase.received,
        preparedImport: prepared,
      ),
    );

    final result = await container
        .read(syncClientControllerProvider.notifier)
        .executePreparedImport(confirmedSensitive: true);

    expect(result, isA<SettingsSyncImportPartialFailure>());
    expect(
      container.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );
    expect(
      container.read(syncClientControllerProvider).preparedImport,
      same(prepared),
    );
  });
}
