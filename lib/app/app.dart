import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_network_logger_provider.dart';
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

class _OhMyLlmAppState extends ConsumerState<OhMyLlmApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) {
      return;
    }
    unawaited(ref.read(appNetworkLoggerProvider).onAppDetached());
  }

  /// 构建顶层 MaterialApp，并交由路由配置管理页面切换。
  @override
  Widget build(BuildContext context) {
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
