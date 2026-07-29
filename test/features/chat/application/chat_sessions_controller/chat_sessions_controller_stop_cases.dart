import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../../../helpers/fake_chat_completion_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// stop / cancel / 迟到回调 / dispose 竞态契约。
void registerChatSessionsControllerStopCases() {
  late ControllerTestHarness harness;
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    harness = ControllerTestHarness();
    await harness.init();
    database = harness.database;
    preferences = harness.preferences;
    fakeClient = harness.fakeClient;
    container = harness.container;
  });
  tearDown(() => harness.dispose());

  Future<void> sendMsg(String content, {Duration? retryDelay}) =>
      harness.sendMsg(content, retryDelay: retryDelay);

  // ── stopStreaming ────────────────────────────────────────────────────────────

  test('stopStreaming 保留已收到的部分回复', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('请开始生成');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分回复'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.last.content, '部分回复');
    expect(state.activeConversation.messages.last.isStreaming, isFalse);
  });

  test('stopStreaming 在无内容时保留空助手占位以便重试', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('不要输出任何内容');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    // 终止后保留空助手占位节点，便于用户重试。
    expect(messages, hasLength(2));
    expect(messages.first.role, ChatMessageRole.user);
    expect(messages.last.role, ChatMessageRole.assistant);
    expect(messages.last.content, isEmpty);
    expect(messages.last.isStreaming, isFalse);
    // 空回复标记指向该助手节点，UI 可显示终止提示卡片。
    expect(state.emptyReplyAssistantId, messages.last.id);
    expect(state.errorMessageAssistantId, messages.last.id);
  });

  test('stopStreaming 在 auto-retry 等待期间取消重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 手动设置 isAutoRetryWaiting 状态
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = container
        .read(chatSessionsProvider)
        .copyWith(
          isAutoRetryWaiting: true,
          autoRetryCount: 3,
          errorMessage: '之前的错误',
        );

    await notifier.stopStreaming();

    final state = container.read(chatSessionsProvider);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.autoRetryCount, 0);
    expect(state.errorMessage, isNull);
  });

  test('stopStreaming 在过渡窗口期间被调用后旧重试不继续', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 第一次请求会失败，重试会有一个可控的等待窗口
    fakeClient.enqueueError(ChatCompletionException('首次失败'));

    // 用较大的 retryDelay 创造宽余的重试窗口，避免 CI timing 脆弱
    final sendFuture = sendMsg(
      'test A',
      retryDelay: const Duration(seconds: 1),
    );

    // 等第一个请求发出并失败，重试循环进入等待窗口
    // 轮询等待 isAutoRetryWaiting 变为 true，最多等 5 秒
    bool waiting = false;
    for (int i = 0; i < 50; i++) {
      waiting = container.read(chatSessionsProvider).isAutoRetryWaiting;
      if (waiting) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(waiting, isTrue);

    // 此时旧重试在等待窗口中，调用 stopStreaming 取消
    await container.read(chatSessionsProvider.notifier).stopStreaming();

    // _isBusy 已为 false（isAutoRetryWaiting 被清除），发送新消息
    fakeClient.enqueueChunks(['回复 B']);
    await sendMsg('test B');

    // 等待旧重试循环退出
    await sendFuture;

    // 只有 2 次请求：test A 的首次失败 + test B 的成功
    // coordinator 以 generation token 守卫，旧重试恢复后不发出额外请求
    expect(fakeClient.requestHistory.length, 2);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '回复 B');
    expect(state.errorMessage, isNull);
    expect(state.isStreaming, isFalse);
  });

  test('stopStreaming 将 emptyReplyAssistantId 指向当前流式占位', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('开始流式');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 手动设置一个伪造的 emptyReplyAssistantId，模拟残留状态。
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');
    expect(
      container.read(chatSessionsProvider).emptyReplyAssistantId,
      'test-id',
    );

    await notifier.stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    // 流式未收到任何内容即被终止，emptyReplyAssistantId 被重置为当前
    // 流式占位节点 id，以便 UI 显示终止提示卡片与重试入口。
    final assistantId =
        state.streamingReply?.assistantMessageId ??
        state.activeConversation.messages
            .lastWhere((m) => m.role == ChatMessageRole.assistant)
            .id;
    expect(state.emptyReplyAssistantId, assistantId);
    expect(state.isStreaming, isFalse);
  });

  // ── stopStreaming 竞态条件 ──────────────────────────────────────────────

  test('stopStreaming 后延迟到达的 onDone 不改变状态', () async {
    // 使用 StreamController 模拟可控的流式生命周期
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试 onDone 竞态');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 终止流式
    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final stateAfterStop = container.read(chatSessionsProvider);
    expect(stateAfterStop.isStreaming, isFalse);
    final contentAfterStop =
        stateAfterStop.activeConversation.messages.last.content;

    // 模拟延迟到达的 onDone：关闭流控制器（触发 Stream onDone）
    streamController.add(const ChatCompletionChunk(contentDelta: '延迟内容'));
    await streamController.close();
    // 让微任务队列执行
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final stateAfterDelayed = container.read(chatSessionsProvider);
    expect(stateAfterDelayed.isStreaming, isFalse);
    // 延迟到达的 chunk 不应改变已有内容
    expect(
      stateAfterDelayed.activeConversation.messages.last.content,
      contentAfterStop,
    );
  });

  test('stopStreaming 后延迟到达的 onError 不改变状态', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试 onError 竞态');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '已有内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final stateAfterStop = container.read(chatSessionsProvider);
    expect(stateAfterStop.isStreaming, isFalse);
    final errorMessageAfterStop = stateAfterStop.errorMessage;

    // 模拟延迟到达的 onError
    streamController.addError(Exception('延迟错误'));
    await streamController.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final stateAfterDelayed = container.read(chatSessionsProvider);
    expect(stateAfterDelayed.isStreaming, isFalse);
    // 延迟到达的错误不应覆盖 stopStreaming 设置的 errorMessage
    expect(stateAfterDelayed.errorMessage, errorMessageAfterStop);
  });

  test('stopStreaming 后再次发送能正常收到新回复', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试标志保持');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    // 开始新一轮流式：旧 generation 的 stop 不应污染新 generation。
    fakeClient.enqueueChunks(['新回复']);
    await sendMsg('新消息');

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages.last.content, '新回复');
  });

  test('连续两次 stopStreaming 不产生异常', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试双击停止');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    // 立即再次调用 stopStreaming（模拟用户快速双击）
    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages.last.content, '部分内容');
  });

  test('stopStreaming 在 cancel() 挂起时仍能一次终止', () async {
    // 模拟 token 空闲间隙：底层订阅的 cancel() 永不完成（socket 无数据）。
    // 修复前 stopStreaming 会 await 该 cancel 而永久挂起，状态无法重置，
    // 需第二次点击才生效；修复后 cancel 即发即忘，单次调用即可终止。
    final streamController = StreamController<ChatCompletionChunk>(
      onCancel: () => Completer<void>().future,
    );
    addTearDown(() => streamController.onCancel = null);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试挂起 cancel');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 用 timeout 作为快速失败守卫：修复前 stopStreaming 会 await 挂起的 cancel
    // 而永不返回，2 秒内即报 TimeoutException；修复后单次调用瞬间完成，不会真等 2 秒。
    await container
        .read(chatSessionsProvider.notifier)
        .stopStreaming()
        .timeout(const Duration(seconds: 2));
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages.last.content, '部分内容');
  });

  test('preparing 阶段 stopStreaming 阻止后续网络请求', () async {
    // 注入 save 被 gate 阻塞的 repository，使 sendMessage 停在 pending save
    // （preparing），coordinator 尚未 start。此时 stop 应完成 completer 并清理，
    // 放行 save 后 _runGenerationViaCoordinator 检测桥接字段已清理而不再 start（P1-1）。
    final slowRepo = _PendingSaveRepository(
      SqliteChatConversationRepository(database),
    );
    final slowContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(slowRepo),
      ],
    );
    addTearDown(slowContainer.dispose);

    final streamController = StreamController<ChatCompletionChunk>();
    // preparing 路径下 coordinator 未 start，streamController 不会被 listen；
    // 单订阅 controller 无消费者时 close 的 done future 不会完成，故 tearDown
    // 只触发 close、不 await 其 done future。
    addTearDown(() {
      streamController.close();
    });
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = slowContainer
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '测试 preparing stop',
          modelConfig: testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    // 等 sendMessage 到达 pending save（preparing）：桥接字段已就位。
    await slowRepo.saveReached!.future;

    await slowContainer.read(chatSessionsProvider.notifier).stopStreaming();

    // 放行 pending save：_runGenerationViaCoordinator 返回后不再 _coordinator.start。
    slowRepo.saveGate!.complete();
    // timeout 守卫：P1-1 修复后 sendFuture 应立即完成；若仍 start 会在此暴露。
    await sendFuture.timeout(const Duration(seconds: 10));

    final state = slowContainer.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(fakeClient.requestHistory, isEmpty);
  });

  test('stopStreaming 等待 Stopped 落盘完成（P2-4）', () async {
    // 注入第 2 次 save（stop 落盘）被 stopSaveGate 阻塞的 repository，验证
    // stopStreaming 在 Stopped 落盘完成前不返回，放行后才返回落盘后的会话。
    final slowRepo = _PendingSaveRepository(
      SqliteChatConversationRepository(database),
    );
    final slowContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(slowRepo),
      ],
    );
    addTearDown(slowContainer.dispose);

    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = slowContainer
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '测试 stop 等待落盘',
          modelConfig: testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    // 等 sendMessage 到达 pending save（第 1 次）并放行，使 generation 进入 streaming。
    await slowRepo.saveReached!.future;
    slowRepo.saveGate!.complete();
    // 投递部分内容使 streaming 非空，stop 时有内容可落盘。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final stopFuture = slowContainer
        .read(chatSessionsProvider.notifier)
        .stopStreaming();
    // 等 stop 落盘（第 2 次 save）到达：Stopped handler 已触发 saveFuture，
    // Cancelled 正在 await 同一 future，stopStreaming 正在 await completer。
    await slowRepo.stopSaveReached!.future;
    // stop 落盘被 stopSaveGate 阻塞：stopStreaming 应等待，不返回。
    await expectLater(
      stopFuture.timeout(const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
    // 放行 stop 落盘：Cancelled complete completer，stopStreaming 返回落盘后的会话。
    slowRepo.stopSaveGate!.complete();
    final stopped = await stopFuture.timeout(const Duration(seconds: 2));
    await sendFuture.timeout(const Duration(seconds: 2));

    final state = slowContainer.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(stopped, isNotNull);
    expect(stopped!.messages.last.content, '部分内容');
  });

  // ── dispose characterization ────────────────────────────────────────────
  //
  // dispose（ref.onDispose 先 completeGeneration(null) 再 coordinator.dispose）
  // 的契约：流式进行中 dispose 后，sendMessage Future 正常完成（不再永久
  // 挂起），迟到事件被 coordinator 的 _disposed guard 静默丢弃，不写已销毁
  // 的 state、不产生未处理异常（P1-2）。

  test('dispose 在流式进行时完成 sendMessage Future 且迟到事件无未处理异常', () async {
    // 独立 container：测试需主动 dispose 触发 controller onDispose，
    // 避免与 setUp tearDown 的 container.dispose() 冲突。
    final disposeContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    var disposed = false;
    addTearDown(() {
      if (!disposed) disposeContainer.dispose();
    });

    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final unexpected = <Object>[];
    await runZonedGuarded(() async {
      final sendFuture = disposeContainer
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '测试 dispose',
            modelConfig: testModel,
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      streamController.add(const ChatCompletionChunk(contentDelta: '部分'));
      await Future<void>.delayed(const Duration(milliseconds: 1));

      disposeContainer.dispose();
      disposed = true;

      // dispose 应完成 sendMessage Future；timeout 守卫确保不再永久挂起（P1-2）。
      await sendFuture.timeout(const Duration(seconds: 2));

      // 订阅取消后迟到事件应静默丢弃，不触发回调、无未处理异常。
      streamController.add(const ChatCompletionChunk(contentDelta: '迟到'));
      await streamController.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }, (error, stack) => unexpected.add(error));

    expect(unexpected, isEmpty);
  });
}

/// 测试用 repository：首次 save 被 [saveGate] 阻塞，用于捕获 preparing 阶段
/// （pending save 进行中、coordinator 尚未 start）的时间窗口。
class _PendingSaveRepository implements ChatConversationRepository {
  _PendingSaveRepository(this._inner);

  final ChatConversationRepository _inner;

  /// 首次 save 完成前阻塞调用方；测试主动 complete 以放行。
  Completer<void>? saveGate = Completer<void>();

  /// saveConversation 首次被调用时 complete，供测试等待 sendMessage 到达
  /// pending save（此时桥接字段已就位、phase=preparing），避免依赖固定 delay。
  Completer<void>? saveReached = Completer<void>();

  /// 第 2 次 save（stop 落盘）完成前阻塞调用方；测试主动 complete 以放行，
  /// 用于验证 stopStreaming 等待 Stopped 落盘完成（P2-4）。
  Completer<void>? stopSaveGate = Completer<void>();

  /// 第 2 次 save 被调用时 complete，供测试等待 stop 落盘到达（Stopped save
  /// 已触发、stopStreaming 正在 await completer），避免依赖固定 delay。
  Completer<void>? stopSaveReached = Completer<void>();

  int _saveCount = 0;

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    _saveCount++;
    if (_saveCount == 1) {
      final reached = saveReached;
      if (reached != null && !reached.isCompleted) {
        reached.complete();
      }
    } else if (_saveCount == 2) {
      final reached = stopSaveReached;
      if (reached != null && !reached.isCompleted) {
        reached.complete();
      }
    }
    await _inner.saveConversation(conversation);
    if (_saveCount == 1) {
      final gate = saveGate;
      if (gate != null) {
        await gate.future;
      }
    } else if (_saveCount == 2) {
      final gate = stopSaveGate;
      if (gate != null) {
        await gate.future;
      }
    }
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) async {
    await _inner.saveConversations(conversations);
    final gate = saveGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  List<ChatConversation> loadAll() => _inner.loadAll();

  @override
  ChatConversation? loadConversation(String id) => _inner.loadConversation(id);

  @override
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) => _inner.loadHistorySummaries(
    keyword: keyword,
    limit: limit,
    offset: offset,
  );

  @override
  int countHistorySummaries({String keyword = ''}) =>
      _inner.countHistorySummaries(keyword: keyword);

  @override
  Future<void> deleteConversations(List<String> ids) =>
      _inner.deleteConversations(ids);

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();
}
