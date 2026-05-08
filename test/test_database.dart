import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_data_migrations.dart';

/// 创建测试用内存数据库，并按正式启动流程执行全部数据迁移。
Future<AppDatabase> createTestDatabase(SharedPreferences preferences) async {
  final database = AppDatabase.inMemory();
  await runAppDataMigrations(preferences: preferences, database: database);
  return database;
}
