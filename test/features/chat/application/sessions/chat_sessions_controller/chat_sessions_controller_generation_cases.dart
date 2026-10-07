import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../../../../helpers/chat/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 生成成功、空回复、失败与请求目标接线；重试和取消由各自的组负责。
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

  test('发送后保存用户模板元数据、助手正文、终止原因和用量', () async {
    const usage = LlmUsage(inputTokens: 100, cachedInputTokens: 25);
    fakeClient.enqueueDeltas(const [
      ChatGenerationChunk(contentDelta: '回复', usage: usage),
      ChatGenerationChunk(finishReason: 'stop'),
    ]);
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

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages, hasLength(2));
    final userMsg = messages.first;
    expect(userMsg.role, ChatMessageRole.user);
    expect(userMsg.content, '问题');
    expect(userMsg.templatePromptId, 'tpl-1');
    expect(userMsg.templateVariableValues, {'key': 'val'});
    expect(userMsg.userMessageSegments, hasLength(1));
    expect(messages.last.role, ChatMessageRole.assistant);
    expect(messages.last.content, '回复');
    expect(messages.last.finishReason, 'stop');
    expect(messages.last.tokenUsage, usage);
    expect(state.isStreaming, isFalse);
    expect(state.generation?.phase, ChatGenerationPhase.succeeded);
    expect(fakeClient.requestedTargets.single.endpoint, testModel.apiUrl);
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
    expect(
      container
          .read(chatSessionsProvider)
          .activeConversation
          .isMessageExcluded(assistantMessageId),
      isTrue,
    );

    fakeClient.enqueueChunks(['第二轮回复']);
    await sendMsg('第二轮问题');

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '第二轮问题'],
    );
  });

  // ── 错误与空回复 ────────────────────────────────────────────────────────────

  test('请求失败保留带用量的空占位和内联错误，关闭自动重试时只发送一次', () async {
    const usage = LlmUsage(
      inputTokens: 100,
      outputTokens: 8,
      cachedInputTokens: 40,
    );
    fakeClient.enqueueError(
      const ChatGenerationException(
        'API 请求失败',
        statusCode: 429,
        responseBody: '{"error":"rate limit exceeded"}',
        usage: usage,
      ),
    );
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('429'));
    expect(state.errorMessage, contains('rate limit exceeded'));
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.first.role, ChatMessageRole.user);
    expect(
      state.activeConversation.messages.last.role,
      ChatMessageRole.assistant,
    );
    expect(state.activeConversation.messages.last.content, isEmpty);
    expect(state.activeConversation.messages.last.tokenUsage, usage);
    expect(
      state.errorMessageAssistantId,
      state.activeConversation.messages.last.id,
    );
    expect(state.emptyReplyAssistantId, isNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(fakeClient.requestHistory, hasLength(1));

    fakeClient.enqueueChunks(['恢复后的回复']);
    await sendMsg('后续问题');
    final recovered = container.read(chatSessionsProvider);
    expect(recovered.activeConversation.messages.last.content, '恢复后的回复');
    expect(recovered.errorMessage, isNull);
    expect(recovered.errorMessageAssistantId, isNull);
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
    fakeClient.enqueueDeltas(const [ChatGenerationChunk(finishReason: 'stop')]);
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
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.last.finishReason, 'stop');
    expect(fakeClient.requestHistory, hasLength(1));
  });

  // ── emptyReplyAssistantId 边界 ──────────────────────────────────────────────

  test('失败后连续空回复的两个错误标识始终指向最新占位', () async {
    // 先模拟错误 -> errorMessageAssistantId 设置，emptyReplyAssistantId 为空
    fakeClient.enqueueError(ChatGenerationException('模拟错误'));
    await sendMsg('触发错误');

    var state = container.read(chatSessionsProvider);
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);

    final failedId = state.errorMessageAssistantId;
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    state = container.read(chatSessionsProvider);
    final firstId = state.emptyReplyAssistantId;
    expect(firstId, state.activeConversation.messages.last.id);
    expect(firstId, isNot(failedId));
    expect(state.errorMessageAssistantId, firstId);

    fakeClient.enqueueChunks(['']); // 第二次空回复
    await sendMsg('第二条');

    state = container.read(chatSessionsProvider);
    expect(
      state.emptyReplyAssistantId,
      state.activeConversation.messages.last.id,
    );
    expect(state.emptyReplyAssistantId, isNot(firstId));
    expect(state.errorMessageAssistantId, state.emptyReplyAssistantId);
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
      // 缺字段时不出现对应小节。
      expect(message, isNot(contains('协议：')));
      expect(message, isNot(contains('请求地址：')));
      expect(message, isNot(contains('API 错误码：')));
    });

    test('携带协议/请求地址/错误码时展开新字段', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final message = controller.formatStreamingError(
        ChatGenerationException(
          '请求失败',
          protocol: LlmApiProtocol.responses,
          uri: Uri.parse('https://api.example.com/v1/responses'),
          apiErrorCode: 'rate_limit_exceeded',
          statusCode: 429,
        ),
        StackTrace.current,
      );

      expect(message, startsWith('请求失败'));
      expect(message, contains('协议：Responses'));
      expect(message, contains('请求地址：https://api.example.com/v1/responses'));
      expect(message, contains('API 错误码：rate_limit_exceeded'));
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

  // ── 原始请求目标接线 ────────────────────────────────────────────────────────

  test('根地址和显式协议原样交给生成客户端', () async {
    const protocol = LlmApiProtocol.responses;
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
      'https://api.example.com',
      reason: protocol.name,
    );
    expect(fakeClient.requestedTargets.last.protocol, protocol);
  });
}

/// 测试用源异常桩，验证 cause 展开。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub(this.message);
  final String message;
  @override
  String toString() => message;
}
