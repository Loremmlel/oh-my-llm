import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_detail_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorites_screen.dart';

import '../../test_database.dart';

Future<void> pumpFavoritesScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
}) async {
  final db = database ?? await createTestDatabase(preferences);
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    db.close();
  });

  await tester.pumpWidget(buildFavoritesApp(preferences, database: db));
  await tester.pumpAndSettle();
}

Widget buildFavoritesApp(
  SharedPreferences preferences, {
  required AppDatabase database,
}) {
  final router = GoRouter(
    initialLocation: AppDestination.favorites.path,
    routes: [
      GoRoute(
        path: AppDestination.favorites.path,
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/favorites/detail',
        builder: (context, state) {
          final favorite = state.extra as Favorite;
          return FavoriteDetailScreen(favorite: favorite);
        },
      ),
      GoRoute(
        path: AppDestination.chat.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('聊天落点'))),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// 在测试数据库中直接写入一条收藏记录。
void seedFavorite(
  AppDatabase database, {
  required String id,
  required String userMessageContent,
  required String assistantContent,
  String assistantReasoningContent = '',
  String? collectionId,
  String? sourceConversationId,
  String? sourceConversationTitle,
  DateTime? createdAt,
}) {
  database.connection.execute(
    'INSERT INTO favorites '
    '(id, collection_id, user_message_content, assistant_content, '
    'assistant_reasoning_content, source_conversation_id, '
    'source_conversation_title, created_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
    [
      id,
      collectionId,
      userMessageContent,
      assistantContent,
      assistantReasoningContent,
      sourceConversationId,
      sourceConversationTitle,
      (createdAt ?? DateTime(2026, 4, 28)).toIso8601String(),
    ],
  );
}

/// 在测试数据库中直接写入一个收藏夹。
void seedCollection(
  AppDatabase database, {
  required String id,
  required String name,
  DateTime? createdAt,
}) {
  database.connection.execute(
    'INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?);',
    [id, name, (createdAt ?? DateTime(2026, 4, 28)).toIso8601String()],
  );
}

Future<SharedPreferences> createEmptyPreferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
