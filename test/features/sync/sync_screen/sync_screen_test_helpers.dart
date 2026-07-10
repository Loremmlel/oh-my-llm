import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/presentation/sync_screen.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_import_confirm_dialog.dart';

import '../../../helpers/test_harness.dart';

Future<AppDatabase> pumpSyncScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1200),
}) async {
  return pumpTestApp(
    tester,
    child: const SyncScreen(),
    preferences: preferences,
    database: database,
    viewportSize: size,
  );
}

Future<void> pumpImportDialog(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required SettingsExportData exportData,
  String sourceDeviceName = 'TestPC',
}) async {
  await pumpTestApp(
    tester,
    preferences: preferences,
    child: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => SyncImportConfirmDialog(
            exportData: exportData,
            sourceDeviceName: sourceDeviceName,
          ),
        ),
        child: const Text('打开对话框'),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pumpAndSettle();
}
