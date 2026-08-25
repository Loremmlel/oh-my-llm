import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_collection_items_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_collections_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_detail_screen.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_route_pages.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../composition/sync_workspace_screen.dart';
import '../composition/video_player_platform_bindings_factory.dart';
import '../navigation/app_destination.dart';

/// 应用顶层路由配置。
///
/// 以 GoRouter 管理顶层页面与子页面跳转。顶层保持平铺 GoRoute；
/// 收藏浏览为三级结构：总览网格 -> 收藏夹内容 -> 收藏详情，详情经
/// pushNamed 进入、pop 回到上一级。初始落地页为聊天页。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(
    videoPlayerBindingsFactory: createAppVideoPlayerBindingsFactory(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// 创建应用 GoRouter，可传入 [initialLocation] 供测试直接打开深链。
///
/// [videoPlayerBindingsFactory] 由 app composition 提供页面级平台 bindings：
/// 每次打开视频时由页面调用一次。测试显式注入 fake 工厂，禁止依赖宿主平台。
///
/// 默认参数必须是编译期常量，而枚举实例属性不能出现在常量表达式中，
/// 故用可空参数 + 运行时兜底指向聊天页。
GoRouter createAppRouter({
  String? initialLocation,
  required VideoPlayerPlatformBindingsFactory videoPlayerBindingsFactory,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppDestination.chat.path,
    routes: [
      GoRoute(
        path: AppDestination.chat.path,
        name: AppDestination.chat.name,
        // 只消费 query 中的可序列化会话 ID；不传 state.extra 实体。
        builder: (context, state) => ChatScreen(
          initialConversationId:
              state.uri.queryParameters[AppRouteParameter.conversationId],
        ),
      ),
      GoRoute(
        path: AppDestination.history.path,
        name: AppDestination.history.name,
        // 只消费 query 中的可序列化浏览窗口参数；校验与夹取在 controller。
        builder: (context, state) => HistoryScreen(
          routeQuery: HistoryBrowseRouteQuery.fromQueryParameters(
            state.uri.queryParameters,
          ),
        ),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        name: AppDestination.settings.name,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppDestination.favorites.path,
        name: AppDestination.favorites.name,
        builder: (context, state) => const FavoriteCollectionsScreen(),
        routes: [
          GoRoute(
            path: 'collections/:${AppRouteParameter.collectionId}',
            name: AppRouteName.favoriteCollectionItems,
            builder: (context, state) => FavoriteCollectionItemsScreen(
              routeCollectionId:
                  state.pathParameters[AppRouteParameter.collectionId],
              routePage: int.tryParse(
                state.uri.queryParameters[AppRouteParameter.page] ?? '',
              ),
              routePageSize: int.tryParse(
                state.uri.queryParameters[AppRouteParameter.pageSize] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: 'items/:${AppRouteParameter.favoriteId}',
            name: AppRouteName.favoriteItemDetail,
            builder: (context, state) => FavoriteDetailScreen(
              favoriteId: state.pathParameters[AppRouteParameter.favoriteId],
            ),
          ),
          // 旧版扁平详情 URL 的兼容入口：必须排在静态 collections/items
          // 之后，且保留段直接回总览，避免被解析成畸形收藏 ID。
          GoRoute(
            path: ':${AppRouteParameter.favoriteId}',
            redirect: (context, state) {
              final favoriteId =
                  state.pathParameters[AppRouteParameter.favoriteId] ?? '';
              if (favoriteId == 'collections' || favoriteId == 'items') {
                return AppDestination.favorites.path;
              }
              return '${AppDestination.favorites.path}/items/$favoriteId';
            },
          ),
        ],
      ),
      GoRoute(
        path: AppDestination.sync.path,
        name: AppDestination.sync.name,
        builder: (context, state) => const SyncWorkspaceScreen(),
        routes: [
          GoRoute(
            path: 'media/image',
            name: AppRouteName.mediaImage,
            builder: (context, state) => MediaImageRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
            ),
          ),
          GoRoute(
            path: 'media/video',
            name: AppRouteName.mediaVideo,
            builder: (context, state) => MediaVideoRoutePage(
              relativePath:
                  state.uri.queryParameters[AppRouteParameter.mediaPath],
              bindingsFactory: videoPlayerBindingsFactory,
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(body: Center(child: Text('未找到页面：${state.uri}')));
    },
  );
}
