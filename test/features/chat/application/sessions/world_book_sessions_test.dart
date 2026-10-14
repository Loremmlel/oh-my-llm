import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/features/chat/application/composer/chat_composer_command.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/requests/chat_context_preview.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/worldbooks/world_books_controller.dart';

import '../../../../helpers/fixtures.dart';
import 'chat_sessions_controller/chat_sessions_controller_test_helpers.dart';

void main() {
  late ControllerTestHarness harness;
  setUp(() async {
    harness = ControllerTestHarness();
    await harness.init();
  });
  tearDown(() => harness.dispose());

  test('对话默认不选，发送快照不受世界书编辑影响，下次请求采用新内容', () async {
    final container = harness.container;
    final controller = container.read(chatSessionsProvider.notifier);
    final book = TestFixtures.worldBook();
    await container.read(worldBooksProvider.notifier).upsert(book);
    expect(
      container.read(activeChatConversationProvider).selectedWorldBookId,
      isNull,
    );
    container.read(chatComposerCommandProvider).selectWorldBook(book.id);
    final original = container.read(activeChatConversationProvider);
    final preview = previewChatContext(
      conversation: original,
      presetPrompt: null,
      worldBook: book,
      body: '开场',
    );
    final stream = harness.fakeClient.enqueueControlledStream();
    final pending = harness.sendMsg('开场');
    await stream.listened;
    expect(
      harness.fakeClient.lastRequestMessages.map((m) => m.content),
      preview.messages.map((m) => m.content),
    );
    final changed = book.copyWith(
      entries: [book.entries.single.copyWith(content: '新世界规则')],
    );
    await container.read(worldBooksProvider.notifier).upsert(changed);
    expect(
      harness.fakeClient.lastRequestMessages.first.content,
      book.promptContent,
    );
    stream.add(const ChatGenerationChunk(contentDelta: '旧请求结束'));
    await stream.close();
    await pending;
    harness.fakeClient.enqueueChunks(['新请求结束']);
    await controller.retryLatestAssistant();
    expect(
      harness.fakeClient.lastRequestMessages.first.content,
      changed.promptContent,
    );
    await controller.createConversation();
    expect(
      container.read(activeChatConversationProvider).selectedWorldBookId,
      isNull,
    );
    controller.selectConversation(original.id);
    expect(
      container.read(activeChatConversationProvider).selectedWorldBookId,
      book.id,
    );
    container.read(chatComposerCommandProvider).selectWorldBook(null);
    expect(
      container.read(activeChatConversationProvider).selectedWorldBookId,
      isNull,
    );
  });

  test('检查点总结传递世界书和预设 CoT 标签，删除世界书后停止注入', () async {
    final container = harness.container;
    final controller = container.read(chatSessionsProvider.notifier);
    final book = TestFixtures.worldBook();
    final preset = TestFixtures.presetPrompt(id: 'custom')
        .copyWith(customReasoningTag: 'thinking_diy');
    await container.read(worldBooksProvider.notifier).upsert(book);
    await container.read(presetPromptsProvider.notifier).upsert(preset);
    controller.updateActiveConversationPreferences(
      selectedWorldBookId: book.id,
      selectedPresetPromptId: preset.id,
    );
    harness.fakeClient.enqueueChunks(['内容']);
    await controller.sendMessage(
      content: '开场',
      modelConfig: testModel,
      presetPrompt: preset,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
    );
    expect(harness.fakeClient.lastRequest!.customReasoningTag, 'thinking_diy');
    harness.fakeClient.enqueueChunks(['总结']);
    await controller.createCheckpoint(
      modelConfig: testModel,
      memoryPrompt: memoryPrompt,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
    );
    expect(harness.fakeClient.lastRequest!.customReasoningTag, 'thinking_diy');
    expect(
      harness.fakeClient.lastRequestMessages.where(
        (m) => m.content == book.promptContent,
      ),
      hasLength(1),
    );
    await container.read(worldBooksProvider.notifier).deleteById(book.id);
    harness.fakeClient.enqueueChunks(['下一轮']);
    await harness.sendMsg('继续');
    expect(
      harness.fakeClient.lastRequestMessages.any(
        (m) => m.content.contains('<world_book'),
      ),
      isFalse,
    );
  });
}
