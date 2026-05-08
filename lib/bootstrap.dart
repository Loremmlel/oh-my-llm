import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/logging/app_network_logger.dart';
import 'core/logging/app_network_logger_provider.dart';
import 'core/persistence/app_data_migrations.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';

/// 应用启动入口：初始化持久化层、执行一次性数据迁移，最后启动 Flutter 应用。
///
/// [sharedPreferences] 仅供测试注入；生产代码传 `null`，由函数内部通过
/// `SharedPreferences.getInstance()` 获取实例。
Future<void> bootstrap({SharedPreferences? sharedPreferences}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();
  final appDatabase = await AppDatabase.open();
  final networkLogger = await AppNetworkLogger.create(
    directoryPath: File(appDatabase.path).parent.path,
  );
  await networkLogger.onAppLaunch();

  // 按顺序执行各数据源的一次性迁移。
  await runAppDataMigrations(preferences: preferences, database: appDatabase);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(appDatabase),
        appNetworkLoggerProvider.overrideWithValue(networkLogger),
      ],
      child: const OhMyLlmApp(),
    ),
  );
}
