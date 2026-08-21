import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/media/helpers/fake_video_player_platform_bindings.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_harness.dart';

/// 测试用的视频 bindings 工厂：显式注入 Fake，禁止依赖宿主 Windows 平台。
VideoPlayerPlatformBindings _mobileTestBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

/// 挂载生产路由下的收藏页面到标准测试环境。
///
/// 使用与生产一致的 [createAppRouter]，避免测试维护平行的路由结构。
/// 若传入 [database] 则使用已有实例（适合预先种子数据的场景），
/// 否则自动创建内存库。
Future<AppDatabase> pumpFavoritesScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
  String? initialLocation,
}) {
  final router = createAppRouter(
    initialLocation: initialLocation ?? AppDestination.favorites.path,
    videoPlayerBindingsFactory: _mobileTestBindings,
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
///
/// 未显式指定 [collectionId] 时归入系统"未分类"收藏夹；
/// [collectionAssignedAt] 缺省与收藏时间同刻。
Favorite seedFavorite(
  AppDatabase database, {
  required String id,
  required String userMessageContent,
  required String assistantContent,
  String assistantReasoningContent = '',
  String assistantModelDisplayName = '匿名模型',
  String? collectionId,
  DateTime? collectionAssignedAt,
  String? sourceConversationId,
  String? sourceConversationTitle,
  String? sourceAssistantMessageId,
  DateTime? createdAt,
}) {
  final resolvedCreatedAt = createdAt ?? DateTime(2026, 4, 28);
  final favorite = Favorite(
    id: id,
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    collectionId:
        collectionId ?? AppReservedEntities.uncategorizedFavoriteCollectionId,
    collectionAssignedAt: collectionAssignedAt ?? resolvedCreatedAt,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
    sourceAssistantMessageId: sourceAssistantMessageId,
    createdAt: resolvedCreatedAt,
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

/// 标准收藏页面测试环境：内存 DB、种子数据、挂载生产路由。
/// [seed] 回调用于预先写入收藏/收藏夹数据，[viewportSize] 控制视口尺寸，
/// [initialLocation] 支持深链直达子路由。返回 [AppDatabase] 供后续验证使用。
Future<AppDatabase> setUpFavoritesScreen(
  WidgetTester tester, {
  Size viewportSize = const Size(1440, 1200),
  void Function(AppDatabase database)? seed,
  String? initialLocation,
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
    initialLocation: initialLocation,
  );
  return database;
}
