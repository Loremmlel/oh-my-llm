import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/composition/cross_feature_bindings.dart';
import 'app/platform/chat_generation_terminal_notification.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_layout_tokens.dart';
import 'core/http/custom_headers_provider.dart';
import 'core/logging/app_network_logger.dart';
import 'core/logging/app_network_logger_provider.dart';
import 'core/logging/network_logger.dart';
import 'core/persistence/app_database.dart';
import 'core/persistence/app_database_provider.dart';
import 'core/persistence/shared_preferences_provider.dart';
import 'core/widgets/app_empty_state.dart';
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
/// [hostPlatform] 仅供测试注入；生产代码传 `null`，由函数内部通过对应
/// `.open()` / `.getInstance()` / `.create()` 获取实例。
///
/// 当传入 [database] 时，[networkLogger] 不会自动按 database 路径创建日志文件，
/// 而是直接使用传入的实例。[database] 与 [networkLogger] 通常成对传入或成对为 null；
/// [sharedPreferences] 可独立注入。测试可用 [hostPlatform] 显式指定平台（避免修改
/// 全局平台状态），并用 [windowsWindowInitializer] 注入 no-op window runtime。
Future<void> bootstrap({
  SharedPreferences? sharedPreferences,
  AppDatabase? database,
  NetworkLogger? networkLogger,
  WindowsWindowInitializer? windowsWindowInitializer,
  TargetPlatform? hostPlatform,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
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
          chatGenerationTerminalNotificationSenderProvider.overrideWithValue(
            createChatGenerationTerminalNotificationSender(
              platform: effectivePlatform,
            ),
          ),
          // 显式把 effectivePlatform 传入 composition：生成前台服务按该平台选
          // 择 Android adapter / no-op，不依赖全局平台状态。
          ...appCompositionOverrides(hostPlatform: effectivePlatform),
        ],
        child: const OhMyLlmApp(),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('应用启动失败：${error.runtimeType}');
    debugPrintStack(stackTrace: stackTrace);
    runApp(_StartupFailureApp(error: error));
  }
}

/// 启动初始化未完成时提供可见、可复制的错误，避免窗口永远停在首帧前。
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'oh_my_llm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppContentWidths.readable,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppEmptyState(
                  icon: Icons.error_outline,
                  title: '应用启动失败',
                  description: '应用未完成初始化。请关闭此窗口，根据下方错误详情处理后重试。',
                  action: SelectableText(
                    error.toString(),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
