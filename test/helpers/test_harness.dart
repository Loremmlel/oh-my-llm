import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_stack.dart';

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
}) async {
  assert(
    child != null || router != null,
    'pumpTestApp requires at least one of child or router',
  );
  final db = database ?? await createTestDatabase(preferences);
  final ownsDatabase = database == null;

  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    if (ownsDatabase) db.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(preferences),
        customHeadersMapProvider.overrideWith((ref) => const {}),
        ...extraOverrides,
      ],
      child: router != null
          ? MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => Stack(
                children: [child!, const NotificationBubbleStack()],
              ),
            )
          : MaterialApp(
              home: child,
              builder: (context, child) => Stack(
                children: [child!, const NotificationBubbleStack()],
              ),
            ),
    ),
  );
  await tester.pump();
  return db;
}
