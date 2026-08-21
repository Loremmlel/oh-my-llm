import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

/// 挂载 HistoryScreen 到标准测试环境。
Future<AppDatabase> pumpHistoryScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size viewportSize = const Size(1440, 1200),
}) async {
  final router = GoRouter(
    initialLocation: AppDestination.history.path,
    routes: [
      GoRoute(
        path: AppDestination.history.path,
        // 与生产 app_router 一致地解析 query，保证测试可驱动深链窗口恢复。
        builder: (context, state) => HistoryScreen(
          routeQuery: HistoryBrowseRouteQuery.fromQueryParameters(
            state.uri.queryParameters,
          ),
        ),
      ),
      GoRoute(
        path: AppDestination.chat.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('聊天落点'))),
      ),
      GoRoute(
        path: AppDestination.settings.path,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  final db = await pumpTestApp(
    tester,
    preferences: preferences,
    database: database,
    viewportSize: viewportSize,
    router: router,
  );
  // GroupedConversationList（ListView.builder + AutomaticKeepAlive）在
  // post-frame 数据注入后，首帧的 KeepAlive child 偶发未完成 layout；
  // 此时 finder 遍历会触发 "RenderBox was not laid out"（全量并发下更易出现）。
  // 额外 pump 一帧让 KeepAlive 结算完整，消除该竞态。属渲染层时序，非数据层异步。
  await tester.pump();
  return db;
}

Future<SharedPreferences> createSeededPreferences(AppDatabase database) async {
  return TestFixtures.seedPreferences(
    database: database,
    conversations: [
      _conversation(
        id: 'conversation-1',
        title: 'Rust 重构计划',
        userMessage: (
          'message-1',
          '帮我整理 Rust 模块边界',
          DateTime(2026, 4, 26, 20, 0),
        ),
        assistantMessage: (
          'message-2',
          '这里包含不应匹配的 assistant 内容',
          DateTime(2026, 4, 26, 20, 1),
        ),
        createdAt: DateTime(2026, 4, 26, 20, 0),
        updatedAt: DateTime(2026, 4, 26, 20, 1),
      ),
      _conversation(
        id: 'conversation-2',
        title: 'Flutter 路线图',
        userMessage: (
          'message-3',
          '请给我一份 Widget 测试清单',
          DateTime(2026, 4, 26, 18, 0),
        ),
        assistantMessage: ('message-4', '当然可以', DateTime(2026, 4, 26, 18, 1)),
        createdAt: DateTime(2026, 4, 26, 18, 0),
        updatedAt: DateTime(2026, 4, 26, 18, 1),
      ),
      _conversation(
        id: 'conversation-3',
        title: '项目复盘',
        userMessage: ('message-5', '请总结本周推进情况', DateTime(2026, 4, 20, 10, 0)),
        assistantMessage: ('message-6', '这里是总结', DateTime(2026, 4, 20, 10, 1)),
        createdAt: DateTime(2026, 4, 20, 10, 0),
        updatedAt: DateTime(2026, 4, 20, 10, 1),
      ),
    ],
  );
}

Future<SharedPreferences> createTreeSeededPreferences(
  AppDatabase database,
) async {
  return TestFixtures.seedPreferences(
    database: database,
    conversations: [
      {
        'id': 'conversation-tree',
        'title': '树状会话',
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
        'selectedPresetPromptId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      },
    ],
  );
}

/// 标准历史页面测试环境：内存 DB、种子对话数据、挂载 HistoryScreen。
/// 返回 [AppDatabase] 供后续验证使用。
Future<AppDatabase> setUpHistoryScreen(WidgetTester tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createSeededPreferences(database);
  await pumpHistoryScreen(tester, preferences: preferences, database: database);
  return database;
}

/// 生成 [count] 条批量会话的偏好种子；时间随序号递减保证排序稳定。
Future<SharedPreferences> createBulkSeededPreferences(
  AppDatabase database, {
  required int count,
}) {
  return TestFixtures.seedPreferences(
    database: database,
    conversations: List.generate(count, (i) {
      final updated = DateTime(2026, 6, 1, 12).subtract(Duration(minutes: i));
      return {
        'id': 'bulk-$i',
        'title': '批量会话 $i',
        'messageNodes': [
          {
            'id': 'bulk-u-$i',
            'role': 'user',
            'content': '批量用户消息 $i',
            'parentId': rootConversationParentId,
            'createdAt': updated.toIso8601String(),
          },
        ],
        'selectedChildByParentId': {rootConversationParentId: 'bulk-u-$i'},
        'createdAt': updated.toIso8601String(),
        'updatedAt': updated.toIso8601String(),
        'selectedModelId': 'model-1',
        'selectedPresetPromptId': null,
        'reasoningEnabled': false,
        'reasoningEffort': 'medium',
      };
    }),
  );
}

/// 同 [setUpHistoryScreen]，但使用 [count] 条批量生成的会话种子，
/// 用于覆盖翻页（默认每页 20 条）场景。
Future<AppDatabase> setUpHistoryScreenWithBulkConversations(
  WidgetTester tester, {
  required int count,
  Size viewportSize = const Size(1440, 1200),
}) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createBulkSeededPreferences(database, count: count);
  await pumpHistoryScreen(
    tester,
    preferences: preferences,
    database: database,
    viewportSize: viewportSize,
  );
  return database;
}

/// 同 [setUpHistoryScreen]，但使用树状分支种子数据。
Future<AppDatabase> setUpHistoryScreenWithTree(WidgetTester tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createTreeSeededPreferences(database);
  await pumpHistoryScreen(tester, preferences: preferences, database: database);
  return database;
}

Map<String, dynamic> _conversation({
  required String id,
  required String title,
  required (String, String, DateTime) userMessage,
  required (String, String, DateTime) assistantMessage,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  final (uId, uContent, uTime) = userMessage;
  final (aId, aContent, aTime) = assistantMessage;

  return {
    'id': id,
    'title': title,
    'messageNodes': [
      {
        'id': uId,
        'role': 'user',
        'content': uContent,
        'parentId': rootConversationParentId,
        'createdAt': uTime.toIso8601String(),
      },
      {
        'id': aId,
        'role': 'assistant',
        'content': aContent,
        'parentId': uId,
        'createdAt': aTime.toIso8601String(),
      },
    ],
    'selectedChildByParentId': {rootConversationParentId: uId, uId: aId},
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'selectedModelId': 'model-1',
    'selectedPresetPromptId': null,
    'reasoningEnabled': false,
    'reasoningEffort': 'medium',
  };
}
