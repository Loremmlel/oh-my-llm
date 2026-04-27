import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

void main() {
  testWidgets('history screen searches only title and user messages', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();

    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildHistoryApp(preferences));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pumpAndSettle();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Widget 测试');
    await tester.pumpAndSettle();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '不应匹配');
    await tester.pumpAndSettle();

    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('history search matches user messages across all branches', (
    tester,
  ) async {
    final preferences = await _createTreeSeededPreferences();

    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildHistoryApp(preferences));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '分支关键词');
    await tester.pumpAndSettle();

    expect(find.text('树状会话'), findsOneWidget);
  });

  testWidgets('history screen renames and batch deletes conversations', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();

    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildHistoryApp(preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名会话').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的历史标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的历史标题'), findsOneWidget);

    await tester.longPress(find.text('新的历史标题'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除 2 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryScreen)),
    );
    final remainingConversations = container
        .read(chatSessionsProvider)
        .conversations
        .where((conversation) => conversation.hasMessages)
        .toList(growable: false);

    expect(remainingConversations.length, 1);
    expect(remainingConversations.single.resolvedTitle, '项目复盘');
  });

  testWidgets('history screen jumps back to chat with selected conversation', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();

    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildHistoryApp(preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flutter 路线图'));
    await tester.pumpAndSettle();

    expect(find.text('聊天落点'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('聊天落点')),
    );
    final activeConversation = container.read(chatSessionsProvider).activeConversation;
    expect(activeConversation.resolvedTitle, 'Flutter 路线图');
  });

  testWidgets('history screen checkbox selects without triggering navigation', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();

    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildHistoryApp(preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('聊天落点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsOneWidget);
  });
}

Widget _buildHistoryApp(SharedPreferences preferences) {
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
          return const Scaffold(
            body: Center(
              child: Text('聊天落点'),
            ),
          );
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
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<SharedPreferences> _createSeededPreferences() async {
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

Future<SharedPreferences> _createTreeSeededPreferences() async {
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
        'selectedChildByParentId': {
          rootConversationParentId: 'u-root-a',
        },
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
