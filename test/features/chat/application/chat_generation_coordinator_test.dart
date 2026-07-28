import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_generation_coordinator.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  // ── 辅助 ─────────────────────────────────────────────────

  late _FakeCompletionClient fakeClient;
  late ChatGenerationCoordinator coordinator;

  setUp(() {
    fakeClient = _FakeCompletionClient();
    coordinator = ChatGenerationCoordinator(client: fakeClient);
  });

  ChatGenerationRequest request({
    String conversationId = 'conv-1',
    String assistantMessageId = 'a1',
  }) {
    return ChatGenerationRequest(
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      modelConfig: const LlmModelConfig(
        id: 'model-1',
        displayName: 'Test',
        apiUrl: 'https://api.example.com/v1/chat/completions',
        apiKey: 'sk-test',
        modelName: 'test-model',
        supportsReasoning: true,
      ),
      messages: const [
        ChatCompletionRequestMessage(role: ChatMessageRole.user, content: 'hi'),
      ],
      retryPolicy: ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: false,
        settings: AutoRetrySettings(),
      ),
    );
  }

  // ── 正常完成 ─────────────────────────────────────────────

  group('正常完成', () {
    test('投递 started/chunk/attemptCompleted(success)，内容累积', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(contentDelta: 'hello'));
      controller.add(
        const ChatCompletionChunk(contentDelta: ' world', finishReason: 'stop'),
      );
      controller.close();

      final started =
          observer.events.firstWhere((e) => e is ChatGenerationStarted)
              as ChatGenerationStarted;
      expect(started.assistantMessageId, 'a1');

      final chunks = observer.events.whereType<ChatGenerationChunk>().toList();
      expect(chunks, hasLength(2));
      expect(chunks[0].contentDelta, 'hello');
      expect(chunks[1].contentDelta, ' world');
      expect(chunks[1].finishReason, 'stop');

      final completed = observer.events
          .whereType<ChatGenerationAttemptCompleted>()
          .single;
      expect(completed.outcome, isA<ChatGenerationSuccess>());
      final success = completed.outcome as ChatGenerationSuccess;
      expect(success.content, 'hello world');
      expect(success.finishReason, 'stop');
    });

    test('reasoning 增量也累积到 success', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(reasoningDelta: '思考'));
      controller.add(
        const ChatCompletionChunk(contentDelta: '正文', finishReason: 'stop'),
      );
      controller.close();

      final success =
          observer.events
                  .whereType<ChatGenerationAttemptCompleted>()
                  .single
                  .outcome
              as ChatGenerationSuccess;
      expect(success.content, '正文');
      expect(success.reasoningContent, '思考');
    });
  });

  // ── 空回复 ───────────────────────────────────────────────

  test('空回复投递 attemptCompleted(emptyReply)', () {
    final controller = StreamController<ChatCompletionChunk>(sync: true);
    addTearDown(controller.close);
    fakeClient.enqueueStream(controller.stream);

    final observer = _CollectingObserver();
    coordinator.start(request(), observer);

    controller.add(const ChatCompletionChunk(finishReason: 'stop'));
    controller.close();

    final completed = observer.events
        .whereType<ChatGenerationAttemptCompleted>()
        .single;
    expect(completed.outcome, isA<ChatGenerationEmptyReply>());
    expect(
      (completed.outcome as ChatGenerationEmptyReply).finishReason,
      'stop',
    );
  });

  // ── 流错误 ───────────────────────────────────────────────

  test('流错误投递 attemptFailed(failure)', () {
    final controller = StreamController<ChatCompletionChunk>(sync: true);
    addTearDown(controller.close);
    fakeClient.enqueueStream(controller.stream);

    final observer = _CollectingObserver();
    coordinator.start(request(), observer);

    controller.addError(Exception('boom'));

    final failed = observer.events
        .whereType<ChatGenerationAttemptFailed>()
        .single;
    expect(failed.outcome, isA<ChatGenerationFailure>());
  });

  // ── 用户 stop ───────────────────────────────────────────

  group('用户 stop', () {
    test('投递 stopped(部分内容) 与 cancelled(userStop)', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(contentDelta: '部分'));
      coordinator.stop();

      final stopped = observer.events.whereType<ChatGenerationStopped>().single;
      expect(stopped.partialContent, '部分');

      final cancelled = observer.events
          .whereType<ChatGenerationCancelledEvent>()
          .single;
      expect(cancelled.reason, ChatCancelReason.userStop);
    });

    test('无内容时 stop 的 partialContent 为空串', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      coordinator.stop();

      final stopped = observer.events.whereType<ChatGenerationStopped>().single;
      expect(stopped.partialContent, '');
    });
  });

  // ── 竞态：迟到回调 ───────────────────────────────────────

  group('迟到回调 guard', () {
    test('stop 后延迟到达的 onDone 不产生新事件', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(contentDelta: '部分'));
      coordinator.stop();
      final countBeforeLate = observer.events.length;

      controller.close();

      expect(observer.events.length, countBeforeLate);
    });

    test('stop 后延迟到达的 onError 不产生新事件', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(contentDelta: '部分'));
      coordinator.stop();
      final countBeforeLate = observer.events.length;

      controller.addError(Exception('延迟错误'));

      expect(observer.events.length, countBeforeLate);
    });

    test('连续 stop 幂等：只产生一次 cancelled', () {
      final controller = StreamController<ChatCompletionChunk>(sync: true);
      addTearDown(controller.close);
      fakeClient.enqueueStream(controller.stream);

      final observer = _CollectingObserver();
      coordinator.start(request(), observer);

      controller.add(const ChatCompletionChunk(contentDelta: '部分'));
      coordinator.stop();
      final countAfterFirstStop = observer.events.length;

      coordinator.stop();

      expect(observer.events.length, countAfterFirstStop);
    });
  });

  // ── supersede ────────────────────────────────────────────

  test('新 generation 启动后旧 attempt 回调被忽略', () {
    final controller1 = StreamController<ChatCompletionChunk>(sync: true);
    final controller2 = StreamController<ChatCompletionChunk>(sync: true);
    addTearDown(controller1.close);
    addTearDown(controller2.close);
    fakeClient.enqueueStream(controller1.stream);
    fakeClient.enqueueStream(controller2.stream);

    final observer = _CollectingObserver();
    coordinator.start(request(assistantMessageId: 'a1'), observer);
    controller1.add(const ChatCompletionChunk(contentDelta: '旧'));

    // 启动新 generation，旧被 supersede。
    coordinator.start(request(assistantMessageId: 'a2'), observer);

    final cancelledForOld = observer.events
        .whereType<ChatGenerationCancelledEvent>()
        .where((e) => e.generationId == 1)
        .single;
    expect(cancelledForOld.reason, ChatCancelReason.superseded);

    final startedNew = observer.events
        .whereType<ChatGenerationStarted>()
        .where((e) => e.generationId == 2)
        .single;
    expect(startedNew.assistantMessageId, 'a2');

    // 旧 generation 延迟 onDone 不应投递 attemptCompleted。
    controller1.close();
    final oldCompleted = observer.events
        .whereType<ChatGenerationAttemptCompleted>()
        .where((e) => e.generationId == 1);
    expect(oldCompleted, isEmpty);

    // 新 generation 正常完成。
    controller2.add(const ChatCompletionChunk(contentDelta: '新'));
    controller2.close();
    final newCompleted = observer.events
        .whereType<ChatGenerationAttemptCompleted>()
        .where((e) => e.generationId == 2)
        .single;
    expect(newCompleted.outcome, isA<ChatGenerationSuccess>());
    expect((newCompleted.outcome as ChatGenerationSuccess).content, '新');
  });

  // ── dispose ─────────────────────────────────────────────

  test('dispose 后迟到事件被忽略', () {
    final controller = StreamController<ChatCompletionChunk>(sync: true);
    addTearDown(controller.close);
    fakeClient.enqueueStream(controller.stream);

    final observer = _CollectingObserver();
    coordinator.start(request(), observer);
    controller.add(const ChatCompletionChunk(contentDelta: '部分'));

    coordinator.dispose();
    final countBeforeLate = observer.events.length;

    controller.add(const ChatCompletionChunk(contentDelta: '迟到'));
    controller.close();

    expect(observer.events.length, countBeforeLate);
  });

  // ── cancel 挂起 ──────────────────────────────────────────

  test('subscription.cancel() 挂起时不阻塞 stop', () {
    // 模拟 token 空闲间隙：底层订阅的 cancel() 永不完成。
    final controller = StreamController<ChatCompletionChunk>(
      sync: true,
      onCancel: () => Completer<void>().future,
    );
    addTearDown(() => controller.onCancel = null);
    fakeClient.enqueueStream(controller.stream);

    final observer = _CollectingObserver();
    coordinator.start(request(), observer);
    controller.add(const ChatCompletionChunk(contentDelta: '部分'));

    // stop 应同步返回，不阻塞在挂起的 cancel。
    coordinator.stop();

    expect(
      observer.events.whereType<ChatGenerationCancelledEvent>().single.reason,
      ChatCancelReason.userStop,
    );
  });
}

/// 仅 override [streamCompletion] 的 fake client，[complete] 继承基类默认实现。
class _FakeCompletionClient extends ChatCompletionClient {
  final List<Stream<ChatCompletionChunk>> _streams = [];

  void enqueueStream(Stream<ChatCompletionChunk> stream) {
    _streams.add(stream);
  }

  @override
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
    Duration? streamIdleTimeout,
  }) {
    if (_streams.isEmpty) {
      throw StateError('No stream enqueued');
    }
    return _streams.removeAt(0);
  }
}

class _CollectingObserver implements ChatGenerationObserver {
  final List<ChatGenerationEvent> events = [];

  @override
  void onGenerationEvent(ChatGenerationEvent event) => events.add(event);
}
