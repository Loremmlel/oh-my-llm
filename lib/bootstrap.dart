import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';
import 'features/chat/data/chat_conversation_migration.dart';
import 'features/chat/data/sqlite_chat_conversation_repository.dart';
import 'features/settings/data/fixed_prompt_sequence_migration.dart';
import 'features/settings/data/prompt_template_migration.dart';
import 'features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'features/settings/data/sqlite_prompt_template_repository.dart';

/// 应用启动入口：初始化持久化层、执行一次性数据迁移，最后启动 Flutter 应用。
///
/// [sharedPreferences] 仅供测试注入；生产代码传 `null`，由函数内部通过
/// `SharedPreferences.getInstance()` 获取实例。
Future<void> bootstrap({SharedPreferences? sharedPreferences}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();
  final appDatabase = await AppDatabase.open();

  // 按顺序执行各数据源的一次性迁移。
  await migrateLegacyChatConversations(
    preferences: preferences,
    repository: SqliteChatConversationRepository(appDatabase),
  );
  await migrateLegacyPromptTemplates(
    preferences: preferences,
    repository: SqlitePromptTemplateRepository(appDatabase),
  );
  await migrateLegacyFixedPromptSequences(
    preferences: preferences,
    repository: SqliteFixedPromptSequenceRepository(appDatabase),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(appDatabase),
      ],
      child: const OhMyLlmApp(),
    ),
  );
}
