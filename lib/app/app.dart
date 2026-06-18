import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/http/http_client_provider.dart';
import '../features/settings/application/font_size_settings_controller.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// 应用根组件，负责接入路由与全局主题。
///
/// 这样可以让启动层保持轻薄，把导航和主题配置集中到各自的 provider
/// 和主题类里，后续维护时更容易定位。
class OhMyLlmApp extends ConsumerStatefulWidget {
  const OhMyLlmApp({super.key});

  @override
  ConsumerState<OhMyLlmApp> createState() => _OhMyLlmAppState();
}

class _OhMyLlmAppState extends ConsumerState<OhMyLlmApp> {
  /// 构建顶层 MaterialApp，并交由路由配置管理页面切换。
  @override
  Widget build(BuildContext context) {
    // 在应用根层 watch，确保 customHeadersSyncProvider 在冷启动后立即可用，
    // 不依赖用户是否访问过设置页。
    ref.watch(customHeadersSyncProvider);

    final fontSizeSettings = ref.watch(fontSizeSettingsProvider);
    final bodyFontSize = fontSizeSettings.bodyFontSize;

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Oh My LLM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(bodyFontSize: bodyFontSize),
      darkTheme: AppTheme.darkTheme(bodyFontSize: bodyFontSize),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
