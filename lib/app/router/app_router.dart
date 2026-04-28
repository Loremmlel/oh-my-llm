import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/presentation/chat_screen.dart';
import '../../features/favorites/domain/models/favorite.dart';
import '../../features/favorites/presentation/favorite_detail_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../navigation/app_destination.dart';

/// 应用顶层路由配置。
///
/// 以 GoRouter 管理聊天、历史对话、设置三个顶层页面之间的跳转，
/// 初始落地页为聊天页。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppDestination.chat.path,
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
      ),
      GoRoute(
        path: '/favorites/detail',
        builder: (context, state) {
          final favorite = state.extra as Favorite;
          return FavoriteDetailScreen(favorite: favorite);
        },
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Text('未找到页面：${state.uri}'),
        ),
      );
    },
  );
});
