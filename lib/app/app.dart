import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// 应用根组件，负责接入路由与全局主题。
///
/// 这样可以让启动层保持轻薄，把导航和主题配置集中到各自的 provider
/// 和主题类里，后续维护时更容易定位。
class OhMyLlmApp extends ConsumerWidget {
  const OhMyLlmApp({super.key});

  /// 构建顶层 MaterialApp，并交由路由配置管理页面切换。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Oh My LLM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
