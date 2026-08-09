/// bootstrap() 集成测试。
///
/// 验证应用完整启动流程：初始化 → 数据迁移 → Provider 注入 → UI 渲染。
/// 所有测试均使用内存数据库和空操作日志记录器，不依赖文件系统或网络。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/bootstrap.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

const _viewportSize = Size(1440, 1024);

void main() {
  testWidgets('正常启动后渲染聊天页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _viewportSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.inMemory();
    addTearDown(() => db.close());

    await bootstrap(database: db, networkLogger: const NoopNetworkLogger());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);

    // 验证导航壳层已渲染（Rail 或 Bar 均可）
    final hasNav =
        find.byType(NavigationRail).evaluate().isNotEmpty ||
        find.byType(NavigationBar).evaluate().isNotEmpty;
    expect(hasNav, isTrue);
  });

  testWidgets('启动后执行了数据迁移', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _viewportSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.inMemory();
    addTearDown(() => db.close());

    await bootstrap(database: db, networkLogger: const NoopNetworkLogger());
    await tester.pump();

    final version =
        db.connection.select('PRAGMA user_version;').single['user_version']
            as int;
    expect(version, greaterThanOrEqualTo(9));
  });

  testWidgets('启动后 ProviderScope override 正确注入', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _viewportSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.inMemory();
    addTearDown(() => db.close());

    await bootstrap(database: db, networkLogger: const NoopNetworkLogger());
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(context);

    final preferences = container.read(sharedPreferencesProvider);
    expect(preferences, isNotNull);

    final database = container.read(appDatabaseProvider);
    expect(database, isNotNull);

    final logger = container.read(appNetworkLoggerProvider);
    expect(logger, isA<NoopNetworkLogger>());

    final completion = container.read(chatGenerationClientProvider);
    expect(completion, isA<OpenAiCompatibleChatClient>());

    final conversation = container.read(chatConversationRepositoryProvider);
    expect(conversation, isA<BackgroundChatConversationRepository>());

    final favorites = container.read(favoritesRepositoryProvider);
    expect(favorites, isA<SqliteFavoritesRepository>());

    final collections = container.read(collectionsRepositoryProvider);
    expect(collections, isA<SqliteCollectionsRepository>());
  });
}
