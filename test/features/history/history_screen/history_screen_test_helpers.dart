import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../test_database.dart';

Future<void> pumpHistoryScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
}) async {
  final database = await createTestDatabase(preferences);
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    database.close();
  });

  await tester.pumpWidget(buildHistoryApp(preferences, database: database));
  await tester.pumpAndSettle();
}

Widget buildHistoryApp(
  SharedPreferences preferences, {
  required AppDatabase database,
}) {
  final router = GoRouter(
    initialLocation: AppDestination.history.path,
    routes: [
      GoRoute(
        path: AppDestination.history.path,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppDestination.chat.path,
        builder: (context, state) {
          return const Scaffold(body: Center(child: Text('聊天落点')));
        },
      ),
      GoRoute(
        path: AppDestination.settings.path,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<SharedPreferences> createSeededPreferences() async {
  SharedPreferences.setMockInitialValues({
    chatConversationsStorageKey: jsonEncode([
      {
        'id': 'conversation-1',
        'title': 'Rust 重构计划',
        'messages': [
          {
            'id': 'message-1',
            'role': 'user',
            'content': '帮我整理 Rust 模块边界',
            'createdAt': DateTime(2026, 4, 26, 20, 0).toIso8601String(),
          },
          {
            'id': 'message-2',
            'role': 'assistant',
            'content': '这里包含不应匹配的 assistant 内容',
            'createdAt': DateTime(2026, 4, 26, 20, 1).toIso8601String(),
          },
        ],
        'createdAt': DateTime(2026, 4, 26, 20, 0).toIso8601String(),
        'updatedAt': DateTime(2026, 4, 26, 20, 1).toIso8601String(),
        'selectedModelId': 'model-1',
        'selectedPromptTemplateId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      },
      {
        'id': 'conversation-2',
        'title': 'Flutter 路线图',
        'messages': [
          {
            'id': 'message-3',
            'role': 'user',
            'content': '请给我一份 Widget 测试清单',
            'createdAt': DateTime(2026, 4, 26, 18, 0).toIso8601String(),
          },
          {
            'id': 'message-4',
            'role': 'assistant',
            'content': '当然可以',
            'createdAt': DateTime(2026, 4, 26, 18, 1).toIso8601String(),
          },
        ],
        'createdAt': DateTime(2026, 4, 26, 18, 0).toIso8601String(),
        'updatedAt': DateTime(2026, 4, 26, 18, 1).toIso8601String(),
        'selectedModelId': 'model-1',
        'selectedPromptTemplateId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      },
      {
        'id': 'conversation-3',
        'title': '项目复盘',
        'messages': [
          {
            'id': 'message-5',
            'role': 'user',
            'content': '请总结本周推进情况',
            'createdAt': DateTime(2026, 4, 20, 10, 0).toIso8601String(),
          },
          {
            'id': 'message-6',
            'role': 'assistant',
            'content': '这里是总结',
            'createdAt': DateTime(2026, 4, 20, 10, 1).toIso8601String(),
          },
        ],
        'createdAt': DateTime(2026, 4, 20, 10, 0).toIso8601String(),
        'updatedAt': DateTime(2026, 4, 20, 10, 1).toIso8601String(),
        'selectedModelId': 'model-1',
        'selectedPromptTemplateId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      },
    ]),
  });

  return SharedPreferences.getInstance();
}

Future<SharedPreferences> createTreeSeededPreferences() async {
  SharedPreferences.setMockInitialValues({
    chatConversationsStorageKey: jsonEncode([
      {
        'id': 'conversation-tree',
        'title': '树状会话',
        'messages': [
          {
            'id': 'u-root-a',
            'role': 'user',
            'content': '当前分支用户消息',
            'createdAt': DateTime(2026, 4, 26, 20, 0).toIso8601String(),
          },
        ],
        'messageNodes': [
          {
            'id': 'u-root-a',
            'role': 'user',
            'content': '当前分支用户消息',
            'parentId': rootConversationParentId,
            'createdAt': DateTime(2026, 4, 26, 20, 0).toIso8601String(),
          },
          {
            'id': 'u-root-b',
            'role': 'user',
            'content': '另一条分支关键词消息',
            'parentId': rootConversationParentId,
            'createdAt': DateTime(2026, 4, 26, 20, 1).toIso8601String(),
          },
        ],
        'selectedChildByParentId': {rootConversationParentId: 'u-root-a'},
        'createdAt': DateTime(2026, 4, 26, 20, 0).toIso8601String(),
        'updatedAt': DateTime(2026, 4, 26, 20, 1).toIso8601String(),
        'selectedModelId': 'model-1',
        'selectedPromptTemplateId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      },
    ]),
  });

  return SharedPreferences.getInstance();
}
