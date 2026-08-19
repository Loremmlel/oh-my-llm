import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/transfer/import_confirm_dialog.dart';

import '../../../../../helpers/async/widget_test_animation.dart';
import '../../../../../helpers/test_harness.dart';

void main() {
  group('ImportConfirmDialog', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    Future<void> pumpHost(
      WidgetTester tester,
      SettingsImportBatch batch, {
      void Function(bool?)? onDialogResult,
    }) async {
      await pumpTestApp(
        tester,
        preferences: preferences,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => ImportConfirmDialog(batch: batch),
                  );
                  onDialogResult?.call(result);
                },
                child: const Text('打开'),
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('打开'));
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsOneWidget);
    }

    testWidgets('导入成功后写入所有 participant 并关闭对话框', (tester) async {
      final writes = <String>[];
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'first',
            label: '第一项',
            write: (value) async => writes.add(value),
          ),
          _FakeParticipant(
            key: 'second',
            label: '第二项',
            order: 1,
            write: (value) async => writes.add(value),
          ),
        ],
        {'first': 'incoming-1', 'second': 'incoming-2'},
      );
      bool? dialogResult;
      await pumpHost(
        tester,
        batch,
        onDialogResult: (result) => dialogResult = result,
      );

      await tester.tap(find.text('导入'));
      await settleOverlayTransition(tester);

      expect(writes, ['incoming-1', 'incoming-2']);
      expect(dialogResult, isTrue);
      expect(find.text('检测到配置导入数据'), findsNothing);
    });

    testWidgets('敏感导入需要勾选确认且摘要不显示敏感值', (tester) async {
      final writes = <String>[];
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'credential',
            label: '凭据设置',
            sensitivity: SettingsTransferSensitivity.credentialBearing,
            write: (value) async => writes.add(value),
          ),
        ],
        {'credential': 'credential-secret'},
      );
      await pumpHost(tester, batch);

      expect(find.textContaining('credential-secret'), findsNothing);
      final importButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导入'),
      );
      expect(importButton.onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('导入'));
      await settleOverlayTransition(tester);

      expect(writes, ['credential-secret']);
      expect(find.text('检测到配置导入数据'), findsNothing);
    });

    testWidgets('本地设置变化时替换 batch、清除确认并阻止写入', (tester) async {
      final writes = <String>[];
      var local = 'old';
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'credential',
            label: '凭据设置',
            sensitivity: SettingsTransferSensitivity.credentialBearing,
            read: () => local,
            includeLocalInFingerprint: true,
            write: (value) async => writes.add(value),
          ),
        ],
        {'credential': 'incoming'},
      );
      local = 'changed';
      await pumpHost(tester, batch);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(writes, isEmpty);
      expect(find.text('本地设置已变化，请重新确认'), findsOneWidget);
      final refreshedImportButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导入'),
      );
      expect(refreshedImportButton.onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('导入'));
      await settleOverlayTransition(tester);
      expect(writes, ['incoming']);
    });

    testWidgets('部分失败时保留对话框并展示完成失败和未执行摘要', (tester) async {
      final writes = <String>[];
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'completed',
            label: '已完成配置',
            write: (value) async => writes.add(value),
          ),
          _FakeParticipant(
            key: 'failed',
            label: '失败配置',
            order: 1,
            write: (_) async => throw StateError('secret failure'),
          ),
          _FakeParticipant(
            key: 'notAttempted',
            label: '未执行配置',
            order: 2,
            write: (value) async => writes.add(value),
          ),
        ],
        {'completed': 'one', 'failed': 'two', 'notAttempted': 'three'},
      );
      await pumpHost(tester, batch);

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(writes, ['one']);
      expect(find.text('检测到配置导入数据'), findsOneWidget);
      expect(find.text('部分配置已导入'), findsOneWidget);
      expect(find.textContaining('已完成配置'), findsWidgets);
      expect(find.textContaining('失败配置'), findsWidgets);
      expect(find.textContaining('未执行配置'), findsWidgets);
      expect(find.textContaining('secret failure'), findsNothing);
    });

    testWidgets('完整失败时保留对话框并展示安全原因', (tester) async {
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'failed',
            label: '失败配置',
            write: (_) async => throw StateError('credential-secret'),
          ),
        ],
        {'failed': 'incoming'},
      );
      await pumpHost(tester, batch);

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(find.text('检测到配置导入数据'), findsOneWidget);
      expect(find.text('写入未完成，请检查本地存储后重试'), findsOneWidget);
      expect(find.textContaining('credential-secret'), findsNothing);
    });

    testWidgets('导入进行中阻止返回并在完成后恢复关闭能力', (tester) async {
      final gate = Completer<void>();
      final writeCompleted = Completer<void>();
      final batch = _buildBatch(
        [
          _FakeParticipant(
            key: 'gated',
            label: '等待写入',
            write: (_) async {
              await gate.future;
              writeCompleted.complete();
              throw StateError('写入失败');
            },
          ),
        ],
        {'gated': 'incoming'},
      );
      await pumpHost(tester, batch);

      await tester.tap(find.text('导入'));
      await tester.pump();
      expect(find.text('导入中...'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );

      await tester.binding.handlePopRoute();
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsOneWidget);

      gate.complete();
      await writeCompleted.future;
      await tester.pump();
      await tester.pump();
      expect(find.text('导入中...'), findsNothing);
      expect(find.text('写入未完成，请检查本地存储后重试'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsNothing);
    });
  });
}

SettingsImportBatch _buildBatch(
  List<_FakeParticipant> participants,
  Map<String, Object?> sections,
) {
  final catalog = SettingsTransferCatalog([
    for (final participant in participants)
      SettingsTransferParticipantBox.erase(participant),
  ]);
  final coordinator = SettingsTransferCoordinator(catalog: catalog);
  final preparation = coordinator.prepareDocument(
    SettingsTransferDocument(sections: sections),
  );
  expect(preparation, isA<SettingsImportReady>());
  return (preparation as SettingsImportReady).batch;
}

final class _FakeParticipant extends ReplacingValueParticipant<String> {
  _FakeParticipant({
    required String key,
    required super.label,
    required this.write,
    this.read,
    super.order = 0,
    super.sensitivity = SettingsTransferSensitivity.standard,
    this.includeLocalInFingerprint = false,
  }) : super(key: SettingsTransferKey(key), group: SettingsTransferGroup.other);

  final Future<void> Function(String value) write;
  final String Function()? read;
  final bool includeLocalInFingerprint;
  String local = 'local';

  @override
  String readLocal() => read?.call() ?? local;

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? payload) => payload as String;

  @override
  bool isEquivalent(String existing, String incoming) => existing == incoming;

  @override
  String fingerprintFor(String value) => includeLocalInFingerprint
      ? '${readLocal()}::$value'
      : super.fingerprintFor(value);

  @override
  Future<void> applyImport(String value) async {
    await write(value);
    local = value;
  }
}
