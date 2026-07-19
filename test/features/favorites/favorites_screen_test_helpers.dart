import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_detail_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorites_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_harness.dart';

/// 挂载 FavoritesScreen 到标准测试环境。
///
/// 若传入 [database] 则使用已有实例（适合预先种子数据的场景），
/// 否则自动创建内存库。
Future<AppDatabase> pumpFavoritesScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
}) async {
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

  return pumpTestApp(
    tester,
    preferences: preferences,
    database: database,
    viewportSize: viewportSize,
    router: router,
  );
}

/// 通过 Repository API 写入一条收藏记录。
Favorite seedFavorite(
  AppDatabase database, {
  required String id,
  required String userMessageContent,
  required String assistantContent,
  String assistantReasoningContent = '',
  String assistantModelDisplayName = '匿名模型',
  String? collectionId,
  String? sourceConversationId,
  String? sourceConversationTitle,
  String? sourceAssistantMessageId,
  DateTime? createdAt,
}) {
  final favorite = Favorite(
    id: id,
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    collectionId: collectionId,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
    sourceAssistantMessageId: sourceAssistantMessageId,
    createdAt: createdAt ?? DateTime(2026, 4, 28),
  );
  SqliteFavoritesRepository(database).save(favorite);
  return favorite;
}

/// 通过 Repository API 写入一个收藏夹。
FavoriteCollection seedCollection(
  AppDatabase database, {
  required String id,
  required String name,
  DateTime? createdAt,
}) {
  final collection = FavoriteCollection(
    id: id,
    name: name,
    createdAt: createdAt ?? DateTime(2026, 4, 28),
  );
  SqliteCollectionsRepository(database).save(collection);
  return collection;
}

Future<SharedPreferences> createEmptyPreferences(AppDatabase database) async {
  return TestFixtures.seedPreferences(database: database);
}

/// 标准收藏页面测试环境：内存 DB、种子数据、挂载 FavoritesScreen。
/// [seed] 回调用于预先写入收藏/收藏夹数据，[viewportSize] 控制视口尺寸。
/// 返回 [AppDatabase] 供后续验证使用。
Future<AppDatabase> setUpFavoritesScreen(
  WidgetTester tester, {
  Size viewportSize = const Size(1440, 1200),
  void Function(AppDatabase database)? seed,
}) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  seed?.call(database);
  final preferences = await createEmptyPreferences(database);
  await pumpFavoritesScreen(
    tester,
    preferences: preferences,
    database: database,
    viewportSize: viewportSize,
  );
  return database;
}
