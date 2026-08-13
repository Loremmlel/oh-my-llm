import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import '../../../helpers/async_test_signals.dart';
import '../../../helpers/fake_chat_generation_client.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';

export '../../../helpers/fake_chat_generation_client.dart';

/// 将默认种子数据写入 SQLite 数据库。
///
/// 种子数据包括：GPT-4.1 模型、代码助手提示词、对比测试流程固定序列。
/// 模型配置写入 SharedPreferences，提示词和序列写入 SQLite。
Future<SharedPreferences> seedDefaultTestData(AppDatabase database) async {
  return TestFixtures.seedPreferences(
    database: database,
    models: [TestFixtures.gpt41()],
    prompts: [TestFixtures.codeAssistantPrompt()],
    sequences: [
      TestFixtures.fixedSequence(
        id: 'sequence-1',
        name: '对比测试流程',
        steps: [
          TestFixtures.sequenceStep(id: 'step-1', content: '请先总结当前实现的核心目标。'),
          TestFixtures.sequenceStep(id: 'step-2', content: '请列出三个可执行方案，并说明权衡。'),
        ],
        updatedAt: DateTime(2026, 4, 27),
      ),
    ],
  );
}

/// 挂载 ChatScreen 到标准测试环境并返回数据库实例。
///
/// 自动创建内存数据库、种子默认数据并注入 ProviderScope。
/// 可通过 [database] 传入已种子数据的外部数据库实例。
Future<AppDatabase> pumpChatScreen(
  WidgetTester tester, {
  required FakeChatGenerationClient fakeClient,
  SharedPreferences? preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1600),
}) async {
  final db = database ?? AppDatabase.inMemory();
  final ownsDatabase = database == null;
  if (ownsDatabase) {
    addTearDown(db.close);
  }

  final prefs = preferences ?? await seedDefaultTestData(db);

  return pumpTestApp(
    tester,
    child: const ChatScreen(),
    preferences: prefs,
    database: db,
    viewportSize: size,
    extraOverrides: [
      chatGenerationClientProvider.overrideWithValue(fakeClient),
    ],
  );
}

/// 持有可复用的 ProviderScope 与 ChatScreen 的卸载/重挂开关。
///
/// 真实 GoRouter 页面切换时 ProviderScope 位于 Navigator 之上、保持存活，
/// 只有 ChatScreen 被销毁重建。直接用 `pumpWidget(SizedBox())` 替换根会连
/// ProviderScope 一起销毁、其内存态（composer draft）随之丢失，无法模拟该
/// 场景。因此用一个 [ValueNotifier] 驱动 scope 的 child，在不动 ProviderScope
/// 的前提下切换是否渲染 ChatScreen。
class ChatScreenMountScope {
  ChatScreenMountScope({required this.scope, required this.showChat});

  /// 可传回 `tester.pumpWidget(scope)` 挂载/重挂的根 widget。
  final ProviderScope scope;

  /// 置 false 卸载 ChatScreen、置 true 重挂，始终保持同一 ProviderScope 存活。
  final ValueNotifier<bool> showChat;
}

/// 挂载 ChatScreen 并返回可复用的 [ChatScreenMountScope]，供卸载/重挂场景使用。
///
/// 与 [pumpChatScreen] 不同，调用方持有 scope 与 [ChatScreenMountScope.showChat]
/// 开关，可在同一 ProviderScope/数据库/SharedPreferences 下卸载并重挂
/// ChatScreen，验证内存态（如 composer draft）跨页面销毁重建仍能恢复。
Future<ChatScreenMountScope> pumpChatScreenScope(
  WidgetTester tester, {
  required FakeChatGenerationClient fakeClient,
  SharedPreferences? preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1600),
}) async {
  final db = database ?? AppDatabase.inMemory();
  final ownsDatabase = database == null;
  if (ownsDatabase) {
    addTearDown(db.close);
  }
  final prefs = preferences ?? await seedDefaultTestData(db);

  final showChat = ValueNotifier<bool>(true);
  final scope = await pumpTestAppScope(
    tester,
    child: ValueListenableBuilder<bool>(
      valueListenable: showChat,
      builder: (context, show, _) =>
          show ? const ChatScreen() : const SizedBox(),
    ),
    viewportSize: size,
    extraOverrides: [
      chatGenerationClientProvider.overrideWithValue(fakeClient),
    ],
    database: db,
    preferences: prefs,
  );
  return ChatScreenMountScope(scope: scope, showChat: showChat);
}

/// composer 输入框：ChatScreen 范围内带「正文」label 的 TextField。
///
/// 用可见 label 定位而非内部 test-key，输入框结构调整时测试不耦合实现细节。
final chatMessageComposerFinder = find.descendant(
  of: find.byType(ChatScreen),
  matching: find.widgetWithText(TextField, '正文'),
);

/// 在聊天输入框中填入内容并点击发送按钮。
Future<void> sendMessage(WidgetTester tester, String content) async {
  await tester.enterText(chatMessageComposerFinder, content);
  final sendButton = find.widgetWithText(FilledButton, '发送');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await tester.pump();
}

/// 等待生成状态满足条件（转调共享 helper，不复制 listener 逻辑）。
///
/// 状态满足后还需等待消息列表布局收敛：新气泡落位与 scroll-to-bottom 同帧
/// 发生，ScrollablePositionedList 需要额外若干帧消除瞬态重复气泡，单帧 pump
/// 不足以稳定（如「展开」按钮/复制按钮会短暂出现两份）。此处按有限组件
/// 动画收敛，与生成完成语义一并封装。
Future<void> waitForChatGeneration(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(ChatSessionsState state) matches, {
  required String description,
}) async {
  await waitForProviderState(
    container: container,
    provider: chatSessionsProvider,
    matches: matches,
    description: description,
  );
  await settleAnimatedWidgetTransition(tester);
}
