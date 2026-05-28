import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/logging/app_network_logger.dart';
import 'core/logging/app_network_logger_provider.dart';
import 'core/logging/network_logger.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';

/// 应用启动入口：初始化持久化层，最后启动 Flutter 应用。
///
/// [sharedPreferences]、[database]、[networkLogger] 仅供测试注入；
/// 生产代码传 `null`，由函数内部通过对应 `.open()` / `.getInstance()` / `.create()` 获取实例。
///
/// 当传入 [database] 时，[networkLogger] 不会自动按 database 路径创建日志文件，
/// 而是直接使用传入的实例。[database] 与 [networkLogger] 通常成对传入或成对为 null；
/// [sharedPreferences] 可独立注入。
Future<void> bootstrap({
  SharedPreferences? sharedPreferences,
  AppDatabase? database,
  NetworkLogger? networkLogger,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();
  final appDatabase = database ?? await AppDatabase.open();
  final logger = networkLogger ??
      await AppNetworkLogger.create(
        directoryPath: File(appDatabase.path).parent.path,
      );
  await logger.onAppLaunch();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(appDatabase),
        appNetworkLoggerProvider.overrideWithValue(logger),
      ],
      child: const OhMyLlmApp(),
    ),
  );
}
