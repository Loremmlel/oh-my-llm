import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/composition/app_attention_bindings.dart';
import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';
import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_stack.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';

import '../test_database.dart';

/// 测试统一使用的固定通知 session ID（合法 v1 eventKey 前缀形态）。
///
/// harness 与集成 helper 统一 override 该值：通知相关断言不依赖时间或
/// 全局随机状态；session 格式本身由对应单元测试覆盖。
const testChatGenerationNotificationSessionId =
    '000102030405060708090a0b0c0d0e0f';

/// harness 默认的通知平台绑定：其他平台 no-op 记录。
///
/// 无论 hostPlatform 取值如何都不创建 Android bridge / Windows host client，
/// 从构造源头保证宿主 CI 不触达任何 MethodChannel；需要 case-specific fake
/// 时经 [pumpTestApp] 的同名参数注入。
ChatGenerationNotificationPlatformBindings
_defaultTestNotificationPlatformBindings() =>
    createOtherPlatformChatGenerationNotificationBindings();

/// 统一的 Widget 测试环境组装工具。
///
/// 封装了内存数据库创建、视口管理、ProviderScope 注入、资源清理等重复逻辑。
///
/// [child] 与 [router] 互斥：传 [router] 时由 GoRouter 首条路由渲染页面，
/// 否则由 [child] 作为 [MaterialApp] 的 home。至少需提供其一。
///
/// 若传入 [database] 参数则使用已有实例（适合预先种子数据的场景），
/// 否则自动创建内存库并在 tearDown 中关闭。始终返回使用的 [AppDatabase] 实例。
///
/// 返回时只保证首帧和同步依赖完成，不承诺动画或异步业务完成；
/// 需要等待动画/业务状态时由调用方按场景使用专门等待 helper。
Future<AppDatabase> pumpTestApp(
  WidgetTester tester, {
  Widget? child,
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
  List<dynamic> extraOverrides = const [],
  GoRouter? router,

  /// 默认 false（与 composition 默认 true 不同是故意的）：widget 测试由
  /// [extraOverrides] 注入 fake completion，故排除生产绑定。
  bool bindChatGenerationClient = false,

  /// 默认 true：保持 SQLite 生产绑定，与 composition 默认一致。
  bool bindChatConversationRepository = true,

  /// 默认 true：保持历史页查询生产绑定（内存库复用同一连接）；测试以
  /// controllable fake 覆盖 [historyPageQueryProvider] 时必须传 false。
  bool bindHistoryPageQuery = true,

  /// 默认 true：保持默认媒体库工厂绑定，与 composition 默认一致；
  /// 测试在 [extraOverrides] 提供 [mediaLibraryFactoryProvider] 覆盖时必须
  /// 传 false 排除生产绑定，避免 Riverpod 重复 override。
  bool bindMediaLibraryFactory = true,

  /// 默认 true：保持生成通知平台绑定（no-op 记录）；测试注入 case-specific
  /// fake 时必须传 false 排除生产绑定后自行 override。
  bool bindChatGenerationNotifications = true,

  /// 默认 true：保持 AppWindow 绑定（no-op 窗口）；测试注入受控窗口时必须
  /// 传 false 排除生产绑定后自行 override。
  bool bindAppWindow = true,

  /// 非 null 时替换 harness 默认的 no-op 平台绑定记录。
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,

  /// 非 null 时替换 harness 默认的 no-op 窗口工厂。
  AppWindowFactory? appWindowFactory,

  /// 默认 true：保持收藏仓库生产绑定；测试以故障注入装饰器覆盖
  /// favorites/collections 仓库时必须传 false。
  bool bindFavoritesRepositories = true,
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
      bindChatGenerationClient: bindChatGenerationClient,
      bindChatConversationRepository: bindChatConversationRepository,
      bindHistoryPageQuery: bindHistoryPageQuery,
      bindMediaLibraryFactory: bindMediaLibraryFactory,
      bindChatGenerationNotifications: bindChatGenerationNotifications,
      bindAppWindow: bindAppWindow,
      notificationPlatformBindingsFactory: notificationPlatformBindingsFactory,
      appWindowFactory: appWindowFactory,
      bindFavoritesRepositories: bindFavoritesRepositories,
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

  /// 默认 false（与 composition 默认 true 不同是故意的）：widget 测试由
  /// [extraOverrides] 注入 fake completion，故排除生产绑定。
  bool bindChatGenerationClient = false,

  /// 默认 true：保持 SQLite 生产绑定，与 composition 默认一致。
  bool bindChatConversationRepository = true,

  /// 默认 true：保持历史页查询生产绑定；测试以 fake 覆盖时传 false。
  bool bindHistoryPageQuery = true,

  /// 默认 true：保持默认媒体库工厂绑定；测试在 [extraOverrides] 提供
  /// [mediaLibraryFactoryProvider] 覆盖时必须传 false。
  bool bindMediaLibraryFactory = true,

  /// 默认 true：保持生成通知平台绑定（no-op 记录）；测试注入 case-specific
  /// fake 时必须传 false 排除生产绑定后自行 override。
  bool bindChatGenerationNotifications = true,

  /// 默认 true：保持 AppWindow 绑定（no-op 窗口）。
  bool bindAppWindow = true,

  /// 非 null 时替换 harness 默认的 no-op 平台绑定记录。
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,

  /// 非 null 时替换 harness 默认的 no-op 窗口工厂。
  AppWindowFactory? appWindowFactory,

  /// 默认 true：保持收藏仓库生产绑定；测试以故障注入装饰器覆盖
  /// favorites/collections 仓库时必须传 false。
  bool bindFavoritesRepositories = true,
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
    bindChatGenerationClient: bindChatGenerationClient,
    bindChatConversationRepository: bindChatConversationRepository,
    bindHistoryPageQuery: bindHistoryPageQuery,
    bindMediaLibraryFactory: bindMediaLibraryFactory,
    bindChatGenerationNotifications: bindChatGenerationNotifications,
    bindAppWindow: bindAppWindow,
    notificationPlatformBindingsFactory: notificationPlatformBindingsFactory,
    appWindowFactory: appWindowFactory,
    bindFavoritesRepositories: bindFavoritesRepositories,
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
  bool bindChatGenerationClient = false,
  bool bindChatConversationRepository = true,
  bool bindHistoryPageQuery = true,
  bool bindMediaLibraryFactory = true,
  bool bindChatGenerationNotifications = true,
  bool bindAppWindow = true,
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,
  AppWindowFactory? appWindowFactory,
  bool bindFavoritesRepositories = true,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(preferences),
      customHeadersMapProvider.overrideWith((ref) => const {}),
      peerHttpClientProvider.overrideWithValue(http.Client()),
      // 固定通知 session：根部装配与收据断言共用同一确定性值。
      chatGenerationNotificationSessionIdProvider.overrideWithValue(
        testChatGenerationNotificationSessionId,
      ),
      // 需要 fake 的 port 从 composition 中排除，由 extraOverrides 接管：
      // Riverpod 禁止同一容器内对同一 provider 重复 override。
      ...appCompositionOverrides(
        useInMemorySyncSecureStore: true,
        bindChatGenerationClient: bindChatGenerationClient,
        bindChatConversationRepository: bindChatConversationRepository,
        bindHistoryPageQuery: bindHistoryPageQuery,
        bindMediaLibraryFactory: bindMediaLibraryFactory,
        bindChatGenerationNotifications: bindChatGenerationNotifications,
        bindAppWindow: bindAppWindow,
        bindFavoritesRepositories: bindFavoritesRepositories,
        // 固定 Windows 宿主：宿主 CI 绝不打开真实 Android MethodChannel；
        // 平台件本身仍由 no-op 工厂提供，Windows host client 也不会被创建。
        hostPlatform: TargetPlatform.windows,
        notificationPlatformBindingsFactory:
            notificationPlatformBindingsFactory ??
            _defaultTestNotificationPlatformBindings,
        appWindowFactory: appWindowFactory ?? () => NoopAppWindow(),
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
