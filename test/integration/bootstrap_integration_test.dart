/// bootstrap() 集成测试。
///
/// 验证启动资源与组合绑定注入、UI 渲染及失败后的资源释放。
/// 所有测试均使用内存数据库和空操作日志记录器，不依赖文件系统或网络。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/bootstrap.dart';
import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _viewportSize = Size(1440, 1024);

Future<
  ({
    ProviderContainer container,
    AppDatabase database,
    SharedPreferences preferences,
    NetworkLogger logger,
  })
>
_pumpBootstrappedApp(
  WidgetTester tester, {
  WindowsWindowInitializer? windowsWindowInitializer,
  TargetPlatform hostPlatform = TargetPlatform.windows,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = _viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  const logger = NoopNetworkLogger();

  await bootstrap(
    database: db,
    networkLogger: logger,
    hostPlatform: hostPlatform,
    windowsWindowInitializer: windowsWindowInitializer ?? () async {},
  );
  await tester.pump();

  final context = tester.element(find.byType(MaterialApp));
  return (
    container: ProviderScope.containerOf(context),
    database: db,
    preferences: preferences,
    logger: logger,
  );
}

void main() {
  testWidgets('Windows 启动一次并渲染聊天导航，注入资源与仓库可用', (tester) async {
    var calls = 0;
    final boot = await _pumpBootstrappedApp(
      tester,
      windowsWindowInitializer: () async => calls++,
    );

    expect(calls, 1);
    expect(find.text('对话'), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
    final container = boot.container;
    expect(container.read(sharedPreferencesProvider), same(boot.preferences));
    expect(container.read(appDatabaseProvider), same(boot.database));
    expect(container.read(appNetworkLoggerProvider), same(boot.logger));
    expect(
      container.read(chatConversationRepositoryProvider).loadAll(),
      isEmpty,
    );
    expect(
      container.read(collectionsRepositoryProvider).loadAll().single.id,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    expect(
      await container
          .read(chatGenerationForegroundServiceProvider)
          .ensureNotificationPermission(),
      ChatNotificationPermissionStatus.notRequired,
    );
  });

  testWidgets('非 Windows 平台不初始化 window runtime，也不篡改全局平台', (tester) async {
    var calls = 0;
    await _pumpBootstrappedApp(
      tester,
      windowsWindowInitializer: () async => calls++,
      // 用 linux 而非 android：android 会绑定真实 MethodChannel adapter，
      // 其命令超时 Timer 在测试环境无法被解析而残留；Android→adapter 的平台
      // 选择契约已由 bindings 测试覆盖，此处只验证非 Windows 不初始化 window。
      hostPlatform: TargetPlatform.linux,
    );

    expect(calls, 0);
    expect(find.byType(MaterialApp), findsOneWidget);
    // bootstrap 通过 hostPlatform 参数显式选择平台，不修改全局平台 override
    expect(debugDefaultTargetPlatformOverride, isNull);
  });

  testWidgets('启动初始化失败时显示错误页并保留原因', (tester) async {
    await bootstrap(
      hostPlatform: TargetPlatform.windows,
      windowsWindowInitializer: () async {
        throw StateError('模拟启动失败');
      },
    );
    await tester.pump();

    expect(find.text('应用启动失败'), findsOneWidget);
    expect(find.textContaining('模拟启动失败'), findsOneWidget);
  });

  testWidgets('日志初始化失败时释放已获取的启动资源', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.inMemory();
    final logger = _FailingStartupNetworkLogger();
    addTearDown(() {
      database.close();
    });

    await bootstrap(
      database: database,
      networkLogger: logger,
      hostPlatform: TargetPlatform.linux,
    );
    await tester.pump();

    expect(find.text('应用启动失败'), findsOneWidget);
    expect(logger.drainCalls, 1);
    expect(() => database.connection.select('SELECT 1;'), throwsA(anything));
  });
}

final class _FailingStartupNetworkLogger with NetworkLogger {
  int drainCalls = 0;

  @override
  Future<void> onAppLaunch() async {
    throw StateError('模拟日志初始化失败');
  }

  @override
  Future<void> drain() async {
    drainCalls++;
  }
}
