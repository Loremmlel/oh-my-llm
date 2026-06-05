import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/sync/presentation/sync_screen.dart';

import '../../../helpers/test_harness.dart';

/// 挂载同步页面并返回测试用数据库实例。
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
