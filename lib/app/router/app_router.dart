import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_detail_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorites_screen.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import '../composition/sync_workspace_screen.dart';
import '../navigation/app_destination.dart';

/// 应用顶层路由配置。
///
/// 以 GoRouter 管理顶层页面与子页面跳转。顶层保持平铺 GoRoute；
/// 收藏详情是 favorites 的 child，经 pushNamed 进入、pop 回到列表。
/// 初始落地页为聊天页。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

/// 创建应用 GoRouter，可传入 [initialLocation] 供测试直接打开深链。
///
/// 默认参数必须是编译期常量，而枚举实例属性不能出现在常量表达式中，
/// 故用可空参数 + 运行时兜底指向聊天页。
GoRouter createAppRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppDestination.chat.path,
    routes: [
      GoRoute(
        path: AppDestination.chat.path,
        name: AppDestination.chat.name,
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: AppDestination.history.path,
        name: AppDestination.history.name,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        name: AppDestination.settings.name,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppDestination.favorites.path,
        name: AppDestination.favorites.name,
        builder: (context, state) => const FavoritesScreen(),
        routes: [
          GoRoute(
            path: ':favoriteId',
            name: AppRouteName.favoriteDetail,
            builder: (context, state) => FavoriteDetailScreen(
              favoriteId: state.pathParameters[AppRouteParameter.favoriteId],
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppDestination.sync.path,
        name: AppDestination.sync.name,
        builder: (context, state) => const SyncWorkspaceScreen(),
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(body: Center(child: Text('未找到页面：${state.uri}')));
    },
  );
}
