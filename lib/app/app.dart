import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_stack.dart';
import 'package:oh_my_llm/features/settings/application/preferences/font_size_settings_controller.dart';
import 'attention/app_attention_observer.dart';
import 'composition/chat_generation_notification_coordinator.dart';
import 'notifications/default_chat_generation_terminal_notifications.dart';
import 'platform/windows_navigation_input_adapter.dart';
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

    // 在应用根层 eager 启动注意力观察者：终态收据的抑制判定依赖注意力快照
    // （生命周期 + 窗口焦点 + 路由），不能等聊天页挂载才开始收集。
    ref.watch(appAttentionStateProvider);

    // 在应用根层 eager 启动终态通知深模块：provider 创建即幂等 start 并消费
    // 冷启动 pending 激活；若等首次 generation 报告才初始化，重启后的通知
    // 点击会丢失。
    ref.watch(chatGenerationTerminalNotificationsProvider);

    // 在应用根层 eager watch 生成通知协调器：生命周期不依赖 ChatScreen 是否
    // 挂载，ChatScreen 未挂载时发起的 generation 也会驱动前台服务通知。
    ref.watch(chatGenerationNotificationCoordinatorProvider);

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
      builder: (context, child) {
        final content = Stack(
          children: [child!, const NotificationBubbleStack()],
        );
        // 仅 Windows 宿主把鼠标后退侧键与 browserBack 翻译成 dispatcher 的
        // 返回请求；其余平台沿用系统返回通道，不新增键盘/指针适配。
        if (defaultTargetPlatform != TargetPlatform.windows) {
          return content;
        }
        return WindowsNavigationInputAdapter(
          // defaultValue 传 false：Router 尚未注册回调时视为未消费。
          onBackRequested: () =>
              router.backButtonDispatcher.invokeCallback(Future.value(false)),
          child: content,
        );
      },
    );
  }
}
