import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_stack.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';

import '../test_database.dart';

/// 统一的 Widget 测试环境组装工具。
///
/// 封装了内存数据库创建、视口管理、ProviderScope 注入、资源清理等重复逻辑。
///
/// [child] 与 [router] 互斥：传 [router] 时由 GoRouter 首条路由渲染页面，
/// 否则由 [child] 作为 [MaterialApp] 的 home。至少需提供其一。
///
/// 若传入 [database] 参数则使用已有实例（适合预先种子数据的场景），
/// 否则自动创建内存库并在 tearDown 中关闭。始终返回使用的 [AppDatabase] 实例。
Future<AppDatabase> pumpTestApp(
  WidgetTester tester, {
  Widget? child,
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
  List<dynamic> extraOverrides = const [],
  GoRouter? router,
  bool bindChatCompletionClient = false,
  bool bindChatConversationRepository = true,
}) async {
  assert(
    child != null || router != null,
    'pumpTestApp requires at least one of child or router',
  );
  final db = database ?? await createTestDatabase(preferences);
  _configureTestView(
    tester,
    viewportSize,
    ownsDatabase: database == null,
    db: db,
  );

  await tester.pumpWidget(
    _buildTestScope(
      db: db,
      preferences: preferences,
      extraOverrides: extraOverrides,
      child: child,
      router: router,
      bindChatCompletionClient: bindChatCompletionClient,
      bindChatConversationRepository: bindChatConversationRepository,
    ),
  );
  await tester.pump();
  return db;
}

/// 返回一个可复用的 [ProviderScope]（不 pump），供测试在保持同一
/// ProviderScope/数据库/SharedPreferences 存活的前提下卸载并重挂 widget。
///
/// 与 [pumpTestApp] 不同，调用方持有 scope，可先 `tester.pumpWidget(const
/// SizedBox())` 卸载子树，再 `tester.pumpWidget(scope)` 重挂，同一
/// ProviderScope 内的内存态（如 composer draft）因此得以保留。
Future<ProviderScope> pumpTestAppScope(
  WidgetTester tester, {
  Widget? child,
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
  List<dynamic> extraOverrides = const [],
  GoRouter? router,
  bool bindChatCompletionClient = false,
  bool bindChatConversationRepository = true,
}) async {
  assert(
    child != null || router != null,
    'pumpTestAppScope requires at least one of child or router',
  );
  final db = database ?? await createTestDatabase(preferences);
  _configureTestView(
    tester,
    viewportSize,
    ownsDatabase: database == null,
    db: db,
  );

  return _buildTestScope(
    db: db,
    preferences: preferences,
    extraOverrides: extraOverrides,
    child: child,
    router: router,
    bindChatCompletionClient: bindChatCompletionClient,
    bindChatConversationRepository: bindChatConversationRepository,
  );
}

void _configureTestView(
  WidgetTester tester,
  Size viewportSize, {
  required bool ownsDatabase,
  required AppDatabase db,
}) {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    if (ownsDatabase) db.close();
  });
}

ProviderScope _buildTestScope({
  required AppDatabase db,
  required SharedPreferences preferences,
  required List<dynamic> extraOverrides,
  Widget? child,
  GoRouter? router,
  bool bindChatCompletionClient = false,
  bool bindChatConversationRepository = true,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(preferences),
      customHeadersMapProvider.overrideWith((ref) => const {}),
      peerHttpClientProvider.overrideWithValue(http.Client()),
      // 需要 fake 的 port 从 composition 中排除，由 extraOverrides 接管：
      // Riverpod 禁止同一容器内对同一 provider 重复 override。
      ...appCompositionOverrides(
        useInMemorySyncSecureStore: true,
        bindChatCompletionClient: bindChatCompletionClient,
        bindChatConversationRepository: bindChatConversationRepository,
      ),
      ...extraOverrides,
    ],
    child: router != null
        ? MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                Stack(children: [child!, const NotificationBubbleStack()]),
          )
        : MaterialApp(
            home: child,
            builder: (context, child) =>
                Stack(children: [child!, const NotificationBubbleStack()]),
          ),
  );
}
