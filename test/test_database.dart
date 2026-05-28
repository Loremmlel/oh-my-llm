import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';

/// 创建测试用内存数据库。
Future<AppDatabase> createTestDatabase(SharedPreferences preferences) async {
  return AppDatabase.inMemory();
}
