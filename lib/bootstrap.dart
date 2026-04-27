import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';
import 'features/chat/data/chat_conversation_migration.dart';
import 'features/chat/data/sqlite_chat_conversation_repository.dart';

Future<void> bootstrap({SharedPreferences? sharedPreferences}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();
  final appDatabase = await AppDatabase.open();
  final chatRepository = SqliteChatConversationRepository(appDatabase);
  await migrateLegacyChatConversations(
    preferences: preferences,
    repository: chatRepository,
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
