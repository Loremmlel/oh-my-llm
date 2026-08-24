import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/composition/app_attention_bindings.dart';
import 'app/composition/chat_generation_notification_platform_bindings.dart';
import 'app/composition/cross_feature_bindings.dart';
import 'core/http/custom_headers_provider.dart';
import 'core/logging/app_network_logger.dart';
import 'core/logging/app_network_logger_provider.dart';
import 'core/logging/network_logger.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';
import 'features/settings/application/preferences/custom_headers_controller.dart';

/// Windows 窗口 runtime 初始化器：仅在 Windows 平台生产 bootstrap 调用一次。
typedef WindowsWindowInitializer = Future<void> Function();

/// 初始化 window_manager 插件 runtime；测试注入 no-op 以避免依赖原生插件注册。
Future<void> initializeWindowsVideoWindowRuntime() async {
  await windowManager.ensureInitialized();
}

/// 应用启动入口：初始化持久化层，最后启动 Flutter 应用。
///
/// [sharedPreferences]、[database]、[networkLogger]、[windowsWindowInitializer]、
/// [hostPlatform]、[notificationPlatformBindingsFactory]、[appWindowFactory]
/// 仅供测试注入；生产代码传 `null`，由函数内部通过对应
/// `.open()` / `.getInstance()` / `.create()` 获取实例。
///
/// 当传入 [database] 时，[networkLogger] 不会自动按 database 路径创建日志文件，
/// 而是直接使用传入的实例。[database] 与 [networkLogger] 通常成对传入或成对为 null；
/// [sharedPreferences] 可独立注入。测试可用 [hostPlatform] 显式指定平台（避免修改
/// 全局平台状态），并用 [windowsWindowInitializer] 注入 no-op window runtime。
///
/// [notificationPlatformBindingsFactory] / [appWindowFactory] 只向
/// `appCompositionOverrides` 透传（替换平台默认工厂的装配来源），不改变
/// [hostPlatform] 的平台判断；测试在 Ubuntu CI 等宿主上选择 Windows 平台时
/// 注入 fake/no-op 工厂即可避免触达真实 MethodChannel 或 window_manager。
Future<void> bootstrap({
  SharedPreferences? sharedPreferences,
  AppDatabase? database,
  NetworkLogger? networkLogger,
  WindowsWindowInitializer? windowsWindowInitializer,
  TargetPlatform? hostPlatform,
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,
  AppWindowFactory? appWindowFactory,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final effectivePlatform = hostPlatform ?? defaultTargetPlatform;
  if (effectivePlatform == TargetPlatform.windows) {
    await (windowsWindowInitializer ?? initializeWindowsVideoWindowRuntime)();
  }

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();
  final appDatabase = database ?? await AppDatabase.open();
  final logger =
      networkLogger ??
      await AppNetworkLogger.create(
        directoryPath: File(appDatabase.path).parent.path,
      );
  await logger.onAppLaunch();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(appDatabase),
        appNetworkLoggerProvider.overrideWithValue(logger),
        // 将 feature 层的 CustomHeadersConfig 映射为 core 层所需的 Map。
        customHeadersMapProvider.overrideWith(
          (ref) => ref.watch(customHeadersProvider).toHeaderMap(),
        ),
        // 显式把 effectivePlatform 传入 composition：生成通知平台件与窗口
        // 端口按该平台选择真实 adapter / no-op，不依赖全局平台状态；测试
        // 注入的 factory 原样透传，只替换装配来源不改平台判断。
        ...appCompositionOverrides(
          hostPlatform: effectivePlatform,
          notificationPlatformBindingsFactory:
              notificationPlatformBindingsFactory,
          appWindowFactory: appWindowFactory,
        ),
      ],
      child: const OhMyLlmApp(),
    ),
  );
}
