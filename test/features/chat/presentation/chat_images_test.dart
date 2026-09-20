import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_image_source.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_image_store.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import '../../../helpers/async/async_test_signals.dart';
import '../../../helpers/async/widget_test_animation.dart';
import '../../../helpers/chat/fake_chat_generation_client.dart';
import '../../../helpers/chat/test_chat_images.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

void main() {
  late TestChatImageSource source;
  late TestChatImageStore store;
  late FakeChatGenerationClient client;
  setUp(() {
    source = TestChatImageSource();
    store = TestChatImageStore();
    client = FakeChatGenerationClient()..enqueueChunks(['收到图片']);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 1200),
  }) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final prefs = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.gpt41()],
    );
    final router = createAppRouter(
      videoPlayerBindingsFactory: () => throw StateError('图片测试不应打开视频'),
    );
    addTearDown(router.dispose);
    await pumpTestApp(
      tester,
      preferences: prefs,
      database: database,
      router: router,
      viewportSize: size,
      extraOverrides: [
        chatGenerationClientProvider.overrideWithValue(client),
        chatImageSourceProvider.overrideWithValue(source),
        chatImageStoreProvider.overrideWithValue(store),
      ],
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
  }

  testWidgets('选择图片可悬停预览并移除，剪贴板图片可单独发送到历史', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pump();
    expect(find.byTooltip('预览图片：测试图片.png'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byTooltip('预览图片：测试图片.png')));
    await tester.pump();
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    await tester.tap(find.byTooltip('预览图片：测试图片.png'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.text('图片预览'), findsOneWidget);
    await tester.tap(find.byTooltip('放大图片'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleAnimatedWidgetTransition(tester);
    await mouse.removePointer();
    await tester.tap(find.byTooltip('移除图片：测试图片.png'));
    await tester.pump();
    expect(find.byTooltip('预览图片：测试图片.png'), findsNothing);
    source.clipboard = (name: testChatImage.name, bytes: testImageBytes);
    await tester.tap(find.widgetWithText(TextField, '正文'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byTooltip('预览图片：测试图片.png'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await waitForProviderState(
      container: container,
      provider: isChatBusyProvider,
      matches: (busy) => !busy,
      description: '图片消息完成',
    );
    expect(client.lastRequest!.messages.last.images, [testChatImage]);
    expect(
      container.read(activeBaseConversationProvider).messageNodes.first.images,
      [testChatImage],
    );
    final id = container.read(activeConversationIdProvider);
    expect(
      container.read(composerDraftProvider.notifier).draftFor(id).images,
      isEmpty,
    );
  });

  testWidgets('普通 Ctrl+V 保留文本粘贴，编辑图片取消后恢复原草稿', (tester) async {
    final container = await pump(tester);
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboardText};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await Clipboard.setData(const ClipboardData(text: '粘贴正文'));
    await tester.tap(find.widgetWithText(TextField, '正文'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('粘贴正文'), findsOneWidget);
    final controller = container.read(chatSessionsProvider.notifier);
    await tester.runAsync(
      () => controller.sendMessage(
        content: '历史图片',
        images: [testChatImage],
        modelConfig: TestFixtures.gpt41(),
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: container
            .read(activeBaseConversationProvider)
            .reasoningEffort,
      ),
    );
    await tester.pump();
    await settleAnimatedWidgetTransition(tester);
    await tester.tap(find.byTooltip('编辑消息'));
    await tester.pump();
    await tester.tap(find.byTooltip('移除图片：测试图片.png'));
    await tester.tap(find.byTooltip('取消编辑'));
    await tester.pump();
    expect(find.text('粘贴正文'), findsOneWidget);
    expect(
      container.read(activeBaseConversationProvider).messageNodes.first.images,
      [testChatImage],
    );
  });

  testWidgets('窄屏选图失败保留草稿且取消编辑丢弃未完成的选图结果', (tester) async {
    final container = await pump(tester, size: const Size(390, 844));
    final controller = container.read(chatSessionsProvider.notifier);
    await tester.runAsync(
      () => controller.sendMessage(
        content: '原消息',
        modelConfig: TestFixtures.gpt41(),
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: container
            .read(activeBaseConversationProvider)
            .reasoningEffort,
      ),
    );
    await tester.pump();
    await settleAnimatedWidgetTransition(tester);
    await tester.tap(find.byTooltip('编辑消息'));
    await tester.pump();
    final selected = Completer<List<SelectedChatImage>>();
    source.pick = () => selected.future;
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pump();
    expect(find.text('正在处理图片…'), findsOneWidget);
    await tester.tap(find.byTooltip('取消编辑'));
    selected.complete([(name: testChatImage.name, bytes: testImageBytes)]);
    await tester.pump();
    expect(find.byTooltip('预览图片：测试图片.png'), findsNothing);
    source.pick = () => Future.error(const FormatException('图片过大，请缩小后重试'));
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pump();
    expect(find.text('图片过大，请缩小后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      container.read(activeBaseConversationProvider).messages.first.role,
      ChatMessageRole.user,
    );
  });
}
