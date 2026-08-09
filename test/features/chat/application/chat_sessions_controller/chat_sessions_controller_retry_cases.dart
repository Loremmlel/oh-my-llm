import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

import '../../../../helpers/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 自动重试策略、异常 finish_reason 重试、retry cap 与空回复重试边界契约。
void registerChatSessionsControllerRetryCases() {
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

  Stream<ChatGenerationChunk> realIdleTimeoutStream({
    Duration idleTimeout = const Duration(milliseconds: 50),
  }) => harness.realIdleTimeoutStream(idleTimeout: idleTimeout);

  // ── 自动重试 ─────────────────────────────────────────────────────────────────

  test('autoRetryEnabled=true 时正常发送并收到回复', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueChunks(['自动重试回复']);

    await sendMsg('你好', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages.length, 2);
    expect(messages.last.content, '自动重试回复');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessageWithAutoRetry 首次失败后重试成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatGenerationException('连接超时'));
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '重试成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessageWithAutoRetry 连续两次失败后第三次成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatGenerationException('第一次失败'));
    fakeClient.enqueueError(ChatGenerationException('第二次失败'));
    fakeClient.enqueueChunks(['第三次成功']);

    await sendMsg('测试多次重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '第三次成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(fakeClient.requestHistory.length, 3);
  });

  test('超时前已收到部分内容仍触发自动重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    // 用真实 ChatCompletionsClient 复现 SSE idle 超时的 async* 时序：
    // 先收到部分内容，再经 fireTimeout 同步 addError + close。修复前
    // completeWithSuccess（onDone）会在 completeWithError（onError）的 await
    // 间隙执行，走成功路径把 completer 完成为非 null，导致自动重试循环误判
    // 成功而终止（红气泡仍显示超时文案却不重试）。
    fakeClient.enqueueStream(realIdleTimeoutStream());
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试超时重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '重试成功');
    expect(fakeClient.requestHistory.length, 2);
    expect(state.errorMessage, isNull);
    expect(state.isStreaming, isFalse);
  });

  test('会话关闭自动重试时 streamIdleTimeout 不生效（依赖对话级开关）', () async {
    // 全局开启超时重试，但会话级自动重试关闭：streamIdleTimeout 不应传给
    // client，避免空闲断开后显示超时错误却不重试（与 retryOnAbnormalFinishReason
    // 同款约束，AutoRetrySettings.retryOnTimeout 文档声明仅在自动重试模式下生效）。
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            retryOnTimeout: true,
            timeoutSeconds: 30,
          ),
        );
    // 不开 autoRetryEnabled（默认 false）

    fakeClient.enqueueChunks(['回复']);

    await sendMsg('测试会话级开关');

    expect(fakeClient.requestedStreamIdleTimeouts.last, isNull);
  });

  test('会话开启自动重试 + retryOnTimeout 时 streamIdleTimeout 生效', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            retryOnTimeout: true,
            timeoutSeconds: 30,
          ),
        );

    fakeClient.enqueueChunks(['回复']);

    await sendMsg('测试生效');

    expect(
      fakeClient.requestedStreamIdleTimeouts.last,
      const Duration(seconds: 30),
    );
  });

  test('sendMessageWithAutoRetry 成功后清除之前的错误信息', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatGenerationException('请求失败'));
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试清除错误', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNull);
    expect(state.errorMessageAssistantId, isNull);
  });

  test('autoRetryWaiting 期间 sendMessage 被 _isBusy 阻止', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 手动设置 isAutoRetryWaiting=true
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = container
        .read(chatSessionsProvider)
        .copyWith(isAutoRetryWaiting: true);

    fakeClient.enqueueChunks(['should not be sent']);
    await sendMsg('不会被发送的消息');

    // _isBusy 应阻止发送，没有请求被发出
    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.hasMessages, isFalse);
    expect(fakeClient.requestHistory, isEmpty);
  });

  test('autoRetryEnabled 默认值在 sendMessage 时不触发自动重试', () async {
    // 不设置 autoRetryEnabled（默认 false）
    fakeClient.enqueueError(ChatGenerationException('错误'));

    await sendMsg('普通发送');

    // 一次请求就失败了，没有重试
    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(fakeClient.requestHistory.length, 1);
  });

  // ── 空回复重试 ────────────────────────────────────────────────────────────────

  test('autoRetry 遇到空回复继续重试直到成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueChunks(['']); // 首次：空回复
    fakeClient.enqueueChunks(['终于成功']); // 重试：正常回复

    await sendMsg('测试空回复重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '终于成功');
    expect(fakeClient.requestHistory.length, 2);
    expect(state.errorMessage, isNull);
    expect(state.emptyReplyAssistantId, isNull);
  });

  test('autoRetry 连续空回复达到上限退出', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 设置 maxRetryCount=2，3 次空回复后触发上限
    final prefs = container.read(sharedPreferencesProvider);
    await prefs.setString(
      'settings.auto_retry',
      '{"maxJitterSeconds":0,"maxRetryCount":2}',
    );
    fakeClient.enqueueChunks(['']); // 第 1 次空
    fakeClient.enqueueChunks(['']); // 第 2 次空
    fakeClient.enqueueChunks(['']); // 第 3 次空（超出上限）

    await sendMsg('测试上限', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('重试已达上限'));
  });

  test('手动重试空回复时删除空节点并重试', () async {
    fakeClient.enqueueChunks(['']); // 空回复
    fakeClient.enqueueChunks(['重试回复']);

    await sendMsg('测试空回复');

    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.length, 2); // user + new assistant
    expect(state.activeConversation.messages.last.content, '重试回复');
    expect(state.errorMessage, isNull);
  });

  test('空回复且无自动重试时不自动重试', () async {
    // autoRetryEnabled 默认 false
    fakeClient.enqueueChunks(['']);

    await sendMsg('测试');

    final state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, isNotNull);
    expect(fakeClient.requestHistory.length, 1); // 仅一次，不重试
  });

  // ── emptyReplyAssistantId 重试边界 ──────────────────────────────────────────

  test('空回后手动重试清除 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    var state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, isNotNull);

    fakeClient.enqueueChunks(['重试回复']);
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNull);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages.last.content, '重试回复');
  });

  // ── fixedInterval 模式 ───────────────────────────────────────────────────────

  test('fixedInterval 模式首次失败后重试成功', () async {
    // 切换到固定间隔模式
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(const AutoRetrySettings(retryMode: RetryMode.fixedInterval));
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatGenerationException('连接超时'));
    fakeClient.enqueueChunks(['固定间隔重试成功']);

    await sendMsg('测试固定间隔重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '固定间隔重试成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
  });

  test('fixedInterval 模式连续失败后第三次成功', () async {
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(const AutoRetrySettings(retryMode: RetryMode.fixedInterval));
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatGenerationException('第一次失败'));
    fakeClient.enqueueError(ChatGenerationException('第二次失败'));
    fakeClient.enqueueChunks(['第三次成功']);

    await sendMsg('固定间隔多次重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '第三次成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(fakeClient.requestHistory.length, 3);
  });

  // ── 异常 finish_reason 重试 ──────────────────────────────────────────────

  test('retryOnAbnormalFinishReason=true 时异常 finish_reason 触发重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 保存带 retryOnAbnormalFinishReason=true 的设置
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // 第一次返回 length（异常），第二次返回 stop（正常）
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '部分内容', finishReason: 'length'),
    ]);
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试异常 finish', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '重试成功');
    expect(state.errorMessage, isNull);
    expect(fakeClient.requestHistory.length, 2);
  });

  test('retryOnAbnormalFinishReason=false 时异常 finish_reason 不触发重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // retryOnAbnormalFinishReason 保持默认 false
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '部分内容', finishReason: 'length'),
    ]);

    await sendMsg('测试不重试');

    final state = container.read(chatSessionsProvider);
    // 不重试，保留异常 finish_reason 的回复
    expect(state.activeConversation.messages.last.content, '部分内容');
    expect(fakeClient.requestHistory.length, 1);
  });

  test('会话关闭自动重试时异常 finish_reason 不触发重试（依赖对话级开关）', () async {
    // 全局开启异常 finish 重试，但会话级自动重试关闭：不应触发重试，也不应
    // 残留「正在自动重试...」红色提示（spec 验证方式 3：依赖对话级开关）。
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );
    // 不开 autoRetryEnabled（默认 false）

    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '部分内容', finishReason: 'length'),
    ]);

    await sendMsg('测试会话级开关');

    final state = container.read(chatSessionsProvider);
    // 保留异常 finish_reason 的回复，不重试
    expect(state.activeConversation.messages.last.content, '部分内容');
    expect(fakeClient.requestHistory.length, 1);
    // 不显示「正在自动重试...」错误提示
    expect(state.errorMessage, isNull);
    expect(state.errorMessageAssistantId, isNull);
  });

  test('stop 不触发异常 finish_reason 重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // stop - 正常完成，不重试
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '正常回复', finishReason: 'stop'),
    ]);

    await sendMsg('测试 stop');

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '正常回复');
    expect(fakeClient.requestHistory.length, 1);
  });

  test('tool_calls 不触发异常 finish_reason 重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // tool_calls - 正常完成，不重试
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(
        contentDelta: '工具调用',
        finishReason: 'tool_calls',
      ),
    ]);

    await sendMsg('测试 tool_calls');

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '工具调用');
    expect(fakeClient.requestHistory.length, 1);
  });

  test('content_filter 触发异常 finish_reason 重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // 第一次返回 content_filter（异常），第二次返回 stop（正常）
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(
        contentDelta: '过滤内容',
        finishReason: 'content_filter',
      ),
    ]);
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试 content_filter', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '重试成功');
    expect(state.errorMessage, isNull);
    expect(fakeClient.requestHistory.length, 2);
  });

  test('异常 finish_reason 时输出规则清空正文则不重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 0,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // 设置输出规则：清空所有内容
    await container
        .read(outputProcessingSettingsProvider.notifier)
        .save(
          const OutputProcessingSettings(
            rules: [
              OutputRegexRule(
                id: 'rule-1',
                title: '清空',
                pattern: '[\\s\\S]*',
                replacement: '',
                enabled: true,
              ),
            ],
          ),
        );

    // 模型返回 length（异常），但输出规则会清空正文
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '一些内容', finishReason: 'length'),
    ]);

    await sendMsg('测试输出规则清空不重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    // 不应该重试（输出规则清空优先级高于异常 finish_reason 重试）
    expect(fakeClient.requestHistory.length, 1);
    // 应显示输出规则清空的错误消息，而非异常 finish_reason 的
    expect(state.errorMessage, ChatErrorMessages.outputRuleEmptied);
  });

  // ── phase/outcome 一一对应 ──────────────────────────────────────────

  test('输出规则清空正文投影 failed + Failure', () async {
    // 设置输出规则：清空所有内容。
    await container
        .read(outputProcessingSettingsProvider.notifier)
        .save(
          const OutputProcessingSettings(
            rules: [
              OutputRegexRule(
                id: 'rule-1',
                title: '清空全部',
                pattern: '[\\s\\S]*',
                replacement: '',
                enabled: true,
              ),
            ],
          ),
        );

    // 正常 finish（finishReason 默认），但输出规则清空正文 -> 分支 4。
    fakeClient.enqueueChunks(['正常内容']);
    await sendMsg('测试规则清空终态');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, ChatErrorMessages.outputRuleEmptied);
    // 输出规则清空正文属于 error，phase=failed + outcome=Failure
    //（非 succeeded + Success），满足 DTO 一一对应。
    expect(state.generation?.phase, ChatGenerationPhase.failed);
    expect(state.generation?.outcome, isA<ChatGenerationFailure>());
  });

  test('异常 finish_reason 达重试上限投影 failed + Failure', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    await container
        .read(autoRetrySettingsProvider.notifier)
        .save(
          const AutoRetrySettings(
            maxJitterSeconds: 0,
            maxRetryCount: 1,
            retryOnAbnormalFinishReason: true,
          ),
        );

    // 异常 finish reason（length），maxRetryCount=1 -> 首次 attempt 即达上限，
    // 不重试。coordinator 投 AttemptCompleted(Success)，但异常 finish 属 error。
    fakeClient.enqueueDeltas([
      const ChatGenerationChunk(contentDelta: '部分内容', finishReason: 'length'),
    ]);

    await sendMsg('测试异常 finish 上限', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(fakeClient.requestHistory.length, 1);
    // 异常 finish（outcome=Success）达上限转 Failure，phase=failed
    //（非 failed + Success），满足 DTO 一一对应。
    expect(state.generation?.phase, ChatGenerationPhase.failed);
    expect(state.generation?.outcome, isA<ChatGenerationFailure>());
  });
}
