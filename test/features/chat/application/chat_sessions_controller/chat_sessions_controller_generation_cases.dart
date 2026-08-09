import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/application/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

import '../../../../helpers/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 生成成功 / 空回复 / 错误 / finish reason / 输出处理与流式错误格式化契约。
void registerChatSessionsControllerGenerationCases() {
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

  // ── sendMessage ────────────────────────────────────────────────────────────

  test('sendMessage 添加用户消息和助手回复', () async {
    fakeClient.enqueueChunks(['你好！']);
    await sendMsg('你好');

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.length, 2);
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[0].content, '你好');
    expect(messages[1].role, ChatMessageRole.assistant);
    expect(messages[1].content, '你好！');
    expect(container.read(chatSessionsProvider).isStreaming, isFalse);
  });

  test('sendMessage 携带模板元数据', () async {
    fakeClient.enqueueChunks(['回复']);
    await container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '问题',
          modelConfig: testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
          templatePromptId: 'tpl-1',
          templateVariableValues: {'key': 'val'},
          userMessageSegments: [
            const UserMessageSegment(
              text: '问题',
              kind: UserMessageSegmentKind.body,
            ),
          ],
        );

    final userMsg = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .first;
    expect(userMsg.templatePromptId, 'tpl-1');
    expect(userMsg.templateVariableValues, {'key': 'val'});
    expect(userMsg.userMessageSegments, hasLength(1));
  });

  test('sendMessage 会裁剪有效输入并忽略纯空白内容', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('  你好  ');

    final notifier = container.read(chatSessionsProvider.notifier);
    await notifier.sendMessage(
      content: '   ',
      modelConfig: testModel,
      presetPrompt: null,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
    );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages, hasLength(2));
    expect(messages[0].content, '你好');
    expect(messages[1].content, '回复');
  });

  test('sendMessage 会跳过已排除的历史消息', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('第一轮问题');

    final assistantMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantMessageId], excluded: true);

    fakeClient.enqueueChunks(['第二轮回复']);
    await sendMsg('第二轮问题');

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '第二轮问题'],
    );
  });

  // ── 错误与空回复 ────────────────────────────────────────────────────────────

  test('sendMessage 错误时设置 errorMessage 并清除 isStreaming', () async {
    fakeClient.enqueueError(ChatGenerationException('API 请求失败'));
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessage 错误且无部分内容时保留空白占位节点', () async {
    fakeClient.enqueueError(ChatGenerationException('请求失败'));
    await sendMsg('触发错误');

    // 空流失败后空白 assistant 节点保留在树中，用户消息 + 占位节点共 2 条
    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages.length, 2);
    expect(messages.first.role, ChatMessageRole.user);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessageAssistantId, isNotNull);
  });

  test('sendMessage 仅收到 reasoning 后失败时保留占位 assistant 节点', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);

    final sendFuture = sendMsg('先思考再失败');
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(reasoningDelta: '思考中'));
    // 等推理增量投影到状态再投递错误：错误与增量按序消费。
    await harness.waitForState(
      (s) => s.streamingReply?.reasoningContent == '思考中',
      description: '推理增量达到期望片段',
    );
    controlled.addError(const ChatGenerationException('请求失败'));
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, startsWith('请求失败'));
    expect(state.activeConversation.messages, hasLength(2));
    expect(
      state.activeConversation.messages.last.role,
      ChatMessageRole.assistant,
    );
    expect(state.activeConversation.messages.last.reasoningContent, '思考中');
    expect(
      state.errorMessageAssistantId,
      state.activeConversation.messages.last.id,
    );
  });

  test('sendMessage 空回复时保留助手占位节点并设置内联错误', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    final state = container.read(chatSessionsProvider);
    expect(
      state.activeConversation.messages.last.role,
      ChatMessageRole.assistant,
    );
    expect(state.activeConversation.messages.last.content, isEmpty);
    expect(
      state.emptyReplyAssistantId,
      state.activeConversation.messages.last.id,
    );
    expect(state.errorMessage, contains('空回复'));
    expect(
      state.errorMessageAssistantId,
      state.activeConversation.messages.last.id,
    );
    expect(state.isStreaming, isFalse);
  });

  test('sendMessage 未知异常时在错误信息中包含堆栈', () async {
    fakeClient.enqueueError(StateError('boom'));
    await sendMsg('触发未知异常');

    final errorMessage = container.read(chatSessionsProvider).errorMessage;
    expect(errorMessage, isNotNull);
    expect(errorMessage, contains('Bad state: boom'));
    expect(errorMessage, contains('```text'));
  });

  test('流式错误且空内容时保留空占位节点并设置内联错误', () async {
    fakeClient.enqueueError(ChatGenerationException('模拟流式错误'));

    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
    // 空白 assistant 节点保留在树中，errorMessageAssistantId 指向它
    expect(state.activeConversation.messages, hasLength(2));
    expect(
      state.errorMessageAssistantId,
      state.activeConversation.messages.last.id,
    );
    expect(
      state.activeConversation.messages.last.role,
      ChatMessageRole.assistant,
    );
    expect(state.activeConversation.messages.last.content, isEmpty);
  });

  test('handleStreamingFailure 空内容不设 emptyReplyAssistantId', () async {
    fakeClient.enqueueError(ChatGenerationException('模拟流式错误'));
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
    expect(state.activeConversation.messages.last.content, isEmpty);
  });

  // ── emptyReplyAssistantId 边界 ──────────────────────────────────────────────

  test('空回复时 errorMessageAssistantId 不会被清除', () async {
    // 先模拟错误 -> errorMessageAssistantId 设置，emptyReplyAssistantId 为空
    fakeClient.enqueueError(ChatGenerationException('模拟错误'));
    await sendMsg('触发错误');

    var state = container.read(chatSessionsProvider);
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);

    // 再模拟空回复 -> emptyReplyAssistantId 设置，errorMessageAssistantId 被清除
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessageAssistantId, isNotNull);
  });

  test('连续两次空回不会残留前一次的 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['']); // 第一次空回复
    await sendMsg('第一条');

    var state = container.read(chatSessionsProvider);
    final firstId = state.emptyReplyAssistantId;
    expect(firstId, isNotNull);

    fakeClient.enqueueChunks(['']); // 第二次空回复
    await sendMsg('第二条');

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNot(firstId));
  });

  test('HTTP 429 错误显示为错误消息而非空回复', () async {
    fakeClient.enqueueError(
      ChatGenerationException('请求失败（429）：rate limit exceeded'),
    );
    await sendMsg('触发 429 错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('429'));
    expect(state.errorMessage, contains('rate limit exceeded'));
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
  });

  test('真正空回复仍走 emptyReplyAssistantId 路径', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    final state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, contains('模型返回了空回复'));
  });

  // ── formatStreamingError ────────────────────────────────────────────────────

  group('formatStreamingError', () {
    test('ChatGenerationException 展开状态码与响应体', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final message = controller.formatStreamingError(
        const ChatGenerationException(
          '请求失败',
          statusCode: 429,
          responseBody: '{"error":"rate limit"}',
        ),
        StackTrace.current,
      );

      expect(message, startsWith('请求失败'));
      expect(message, contains('429'));
      expect(message, contains('rate limit'));
    });

    test('超长响应体被截断并附省略提示', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final hugeBody = 'x' * 5000;
      final message = controller.formatStreamingError(
        ChatGenerationException(
          '请求失败',
          statusCode: 500,
          responseBody: hugeBody,
        ),
        StackTrace.current,
      );

      expect(message, contains('已截断'));
      expect(message.length, lessThan(hugeBody.length));
    });

    test('携带源异常时展开 cause', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final message = controller.formatStreamingError(
        ChatGenerationException(
          '连接失败',
          cause: const SocketExceptionStub('连接被重置'),
          causeStackTrace: StackTrace.current,
        ),
        StackTrace.current,
      );

      expect(message, startsWith('连接失败'));
      expect(message, contains('连接被重置'));
    });

    test('非 ChatGenerationException 降级为 toString + 堆栈', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final message = controller.formatStreamingError(
        StateError('未知错误'),
        StackTrace.current,
      );

      expect(message, contains('未知错误'));
      expect(message, contains('```text'));
    });
  });

  // ── finishReason 传递 ───────────────────────────────────────────────────────

  group('finishReason 传递', () {
    test('正常完成时 finishReason 写入消息', () async {
      // 模拟 chunk 序列：content chunk（无 finishReason）-> 空 chunk 带 finishReason
      fakeClient.enqueueDeltas(const [
        ChatGenerationChunk(contentDelta: '你好'),
        ChatGenerationChunk(finishReason: 'stop'),
      ]);
      await sendMsg('测试 finishReason');

      final state = container.read(chatSessionsProvider);
      final assistant = state.activeConversation.messages.last;
      expect(assistant.role, ChatMessageRole.assistant);
      expect(assistant.content, '你好');
      expect(assistant.finishReason, 'stop');
    });

    test('空回复时 finishReason 仍保留', () async {
      // 空内容 chunk 带 finishReason，走 emptyReply 路径
      fakeClient.enqueueDeltas(const [
        ChatGenerationChunk(finishReason: 'stop'),
      ]);
      await sendMsg('空回复带 finishReason');

      final state = container.read(chatSessionsProvider);
      final assistant = state.activeConversation.messages.last;
      expect(assistant.role, ChatMessageRole.assistant);
      expect(assistant.content, isEmpty);
      // 空回复路径仍通过 replaceAssistantMessageInTree 传入 finishReason
      expect(assistant.finishReason, 'stop');
      expect(state.emptyReplyAssistantId, assistant.id);
    });

    test('stopStreaming 路径保留已收到的 finishReason', () async {
      final controlled = fakeClient.enqueueControlledStream();
      addTearDown(controlled.close);

      final sendFuture = sendMsg('测试中断 finishReason');
      await controlled.listened;
      // 发送带 finishReason 的 chunk，随后中断流式
      controlled.add(
        const ChatGenerationChunk(contentDelta: '部分内容', finishReason: 'stop'),
      );
      // 等 chunk 消费完成（run 的累积缓冲含 finishReason）再 stop，
      // 保证 stop 快照保留 finishReason。
      await harness.waitForState(
        (s) => s.streamingReply?.content == '部分内容',
        description: '流式内容达到期望片段',
      );

      await container.read(chatSessionsProvider.notifier).stopStreaming();
      await sendFuture;

      final state = container.read(chatSessionsProvider);
      final assistant = state.activeConversation.messages.last;
      expect(assistant.role, ChatMessageRole.assistant);
      expect(assistant.content, '部分内容');
      // stopStreaming 通过 buildConversationAfterStreamingInterrupt 保留 finishReason
      expect(assistant.finishReason, 'stop');
    });
  });

  // ── 生成端点解析（LlmEndpointResolver 接线）─────────────────────────────────

  test('apiUrl 为根地址时 wire 请求解析后的完整生成端点（三协议参数化）', () async {
    const cases = <(LlmApiProtocol, String)>[
      (
        LlmApiProtocol.chatCompletions,
        'https://api.example.com/v1/chat/completions',
      ),
      (LlmApiProtocol.responses, 'https://api.example.com/v1/responses'),
      (LlmApiProtocol.anthropic, 'https://api.example.com/v1/messages'),
    ];

    for (final (protocol, expectedEndpoint) in cases) {
      fakeClient.enqueueChunks(['回复']);
      await container
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '问题',
            modelConfig: testModel.copyWith(
              apiProtocol: protocol,
              apiUrl: 'https://api.example.com',
            ),
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      expect(
        fakeClient.requestedTargets.last.endpoint,
        expectedEndpoint,
        reason: protocol.name,
      );
    }
  });

  test('apiUrl 为完整生成端点时 wire 上 URL 原样（resolver 幂等）', () async {
    fakeClient.enqueueChunks(['回复']);
    await harness.sendMsg('问题');

    expect(
      fakeClient.requestedTargets.last.endpoint,
      'https://api.example.com/v1/chat/completions',
    );
  });

  test('apiUrl 无法解析时以 inline assistant 错误展示而非崩溃', () async {
    await container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '问题',
          modelConfig: testModel.copyWith(apiUrl: 'not-a-url'),
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('not-a-url'));
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.isStreaming, isFalse);

    // run 已终止（非悬挂）：后续消息可正常发送。
    fakeClient.enqueueChunks(['正常回复']);
    await harness.sendMsg('后续问题');
    expect(
      container
          .read(chatSessionsProvider)
          .activeConversation
          .messages
          .last
          .content,
      '正常回复',
    );
  });

  // ── 输出处理正则清空回复 ─────────────────────────────────────────────────────

  group('输出处理正则清空回复', () {
    test('规则把非空正文清空时提示错误且不触发自动重试', () async {
      await container
          .read(outputProcessingSettingsProvider.notifier)
          .save(
            const OutputProcessingSettings(
              rules: [
                OutputRegexRule(
                  id: 'rule-1',
                  title: '删除全部',
                  pattern: '你好',
                  replacement: '',
                  order: 0,
                  enabled: true,
                ),
              ],
            ),
          );

      fakeClient.enqueueChunks(['你好']);
      await sendMsg('触发清空');

      final state = container.read(chatSessionsProvider);
      expect(state.errorMessage, ChatErrorMessages.outputRuleEmptied);
      expect(state.emptyReplyAssistantId, isNull);
      expect(state.errorMessageAssistantId, isNotNull);
      expect(state.isStreaming, isFalse);
    });
  });
}

/// 测试用源异常桩，验证 cause 展开。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub(this.message);
  final String message;
  @override
  String toString() => message;
}
