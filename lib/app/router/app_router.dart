import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/presentation/chat_placeholder_screen.dart';
import '../../features/history/presentation/history_placeholder_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../navigation/app_destination.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppDestination.chat.path,
    routes: [
      GoRoute(
        path: AppDestination.chat.path,
        name: AppDestination.chat.name,
        builder: (context, state) => const ChatPlaceholderScreen(),
      ),
      GoRoute(
        path: AppDestination.history.path,
        name: AppDestination.history.name,
        builder: (context, state) => const HistoryPlaceholderScreen(),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        name: AppDestination.settings.name,
        builder: (context, state) => const SettingsScreen(),
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
