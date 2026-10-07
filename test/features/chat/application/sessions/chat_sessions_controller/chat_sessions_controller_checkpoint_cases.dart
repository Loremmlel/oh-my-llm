import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../../../../../helpers/chat/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 检查点创建、链式 context、excluded messages、applied title 与 generation 互斥契约。
void registerChatSessionsControllerCheckpointCases() {
  late ControllerTestHarness harness;
  late FakeChatGenerationClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    harness = ControllerTestHarness();
    await harness.init();
    fakeClient = harness.fakeClient;
    container = harness.container;
  });
  tearDown(() => harness.dispose());

  Future<void> sendMsg(String content, {Duration? retryDelay}) =>
      harness.sendMsg(content, retryDelay: retryDelay);

  test('创建检查点附带当前预设并过滤历史，保存总结和来源名称', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('需要带前置提示词的上下文');
    final assistantId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantId], excluded: true);
    await container
        .read(presetPromptsProvider.notifier)
        .upsert(
          PresetPrompt(
            id: 'prompt-1',
            name: '模板一',
            messages: const [
              PromptMessage(
                id: 'prompt-1-message-1',
                role: PromptMessageRole.user,
                content: '模板一前置',
                placement: PromptMessagePlacement.before,
              ),
            ],
            updatedAt: DateTime(2026, 4, 30),
          ),
        );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: 'prompt-1',
        );

    fakeClient.enqueueChunks(['检查点总结']);
    final checkpoint = await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: testModel,
          memoryPrompt: memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final requestContents = fakeClient.lastRequestMessages
        .map((message) => message.content)
        .toList(growable: false);
    expect(requestContents, contains('模板一前置'));
    expect(requestContents, contains('需要带前置提示词的上下文'));
    expect(requestContents, isNot(contains('首轮回复')));
    expect(requestContents.last, contains('请按照以下记忆总结提示词生成新的检查点'));
    expect(requestContents.last, contains('请总结当前对话中的关键事实、约束与待办。'));
    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.checkpoints, hasLength(1));
    expect(state.activeConversation.checkpoints.single.id, checkpoint.id);
    expect(state.activeConversation.checkpoints.single.content, '检查点总结');
    expect(
      state.activeConversation.checkpoints.single.sourceMemoryPromptName,
      '研发总结',
    );
    expect(state.isCheckpointing, isFalse);
  });

  test('选中检查点后发送消息只携带检查点 system 消息与增量消息', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('第一轮问题');

    fakeClient.enqueueChunks(['检查点总结']);
    final checkpoint = await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: testModel,
          memoryPrompt: memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    container
        .read(chatSessionsProvider.notifier)
        .selectActiveCheckpoint(checkpoint.id);

    fakeClient.enqueueChunks(['第二轮回复']);
    await sendMsg('第二轮问题');

    final lastRequest = fakeClient.requestHistory.last;
    expect(lastRequest, hasLength(2));
    expect(lastRequest.first.role, ChatMessageRole.system);
    expect(lastRequest.first.content, contains('检查点 1'));
    expect(lastRequest.first.content, contains('检查点总结'));
    expect(lastRequest.last.role, ChatMessageRole.user);
    expect(lastRequest.last.content, '第二轮问题');
    final assistant = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last;
    expect(assistant.role, ChatMessageRole.assistant);
    expect(assistant.content, '第二轮回复');
    expect(assistant.appliedCheckpointTitle, '检查点 1');
  });
}
