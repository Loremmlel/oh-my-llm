import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

import '../../../helpers/controllable_chat_conversation_repository.dart';
import '../../../helpers/fake_chat_completion_client.dart';

/// generation 生命周期的串行化竞态契约。
///
/// 这些测试用 [ControllableChatConversationRepository] 的 gate 在 generation
/// 关键 checkpoint（pending / terminal / stop save）真正写入前精确同步，
/// 验证《Phase 9 - Generation Lifecycle 修复计划》第四节"必须成立的不变量"。
/// 不依赖毫秒级 timing：所有时序由 gate 的 reached / release 决定。
///
/// 修复前这些用例暴露旧 bridge 的竞态（红）；Task 3 切换到串行 run 后启用并转绿。
void main() {
  late AppDatabase database;
  late ControllableChatConversationRepository repository;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
        items: const [
          LlmProviderConfig(
            id: 'provider-1',
            name: 'Test Provider',
            apiUrl: 'https://api.example.com/v1/chat/completions',
            apiKey: 'sk-test',
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'Test Model',
                modelName: 'test-model',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        toJson: (provider) => provider.toJson(),
      ),
    });
    database = AppDatabase.inMemory();
    repository = ControllableChatConversationRepository(database);
    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() {
      container.dispose();
      database.close();
    });
  });

  Future<void> sendMsg(String content, {Duration? retryDelay}) => container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: content,
        modelConfig: _testModel,
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
        retryDelay: retryDelay,
      );

  const defaultTimeout = Duration(seconds: 5);

  // 整组跳过：待 Task 3 串行 run 切换后启用。修复前为红，切换后转绿。
  group('serialized generation run contract', () {
    test('同一事件循环并发发送只接纳第一个 command', () async {
      repository.gateSave(1);
      fakeClient.enqueueChunks(['A-reply']);

      final sendA = sendMsg('AAA');
      final sendB = sendMsg('BBB');
      await sendB.timeout(defaultTimeout);
      await repository.awaitReached(1);

      var state = container.read(chatSessionsProvider);
      expect(fakeClient.requestHistory, isEmpty);
      expect(
        state.activeConversation.messages.any((m) => m.content == 'BBB'),
        isFalse,
      );

      repository.releaseSave(1);
      await sendA.timeout(defaultTimeout);

      state = container.read(chatSessionsProvider);
      expect(fakeClient.requestHistory, hasLength(1));
      expect(
        state.activeConversation.messages.any((m) => m.content == 'AAA'),
        isTrue,
      );
      expect(
        state.activeConversation.messages.any((m) => m.content == 'BBB'),
        isFalse,
      );
      expect(state.activeConversation.messages.last.content, 'A-reply');
    });

    // ── 不变量 5：旧 run terminal durable 完成前新 command 被拒 ──────────────────
    test('A preparing stop 的 stop save 期间保持 busy，新 command 被拒', () async {
      repository.gateSave(1); // A pending save
      repository.gateSave(2); // A stop save
      final streamController = StreamController<ChatCompletionChunk>();
      // preparing stop 路径下 streamController 不会被 listen，单订阅 controller 无
      // 消费者时 close 的 done future 不完成；用 void lambda 避免 tearDown await 它。
      addTearDown(() {
        streamController.close();
      });
      fakeClient.enqueueStream(streamController.stream);

      final sendAFuture = sendMsg('AAA');
      await repository.awaitReached(1); // A 停在 preparing（pending save）

      // preparing stop：记录停止意图，等待 pending save 后串行写 stop save。
      final stopAFuture = container
          .read(chatSessionsProvider.notifier)
          .stopStreaming();
      repository.releaseSave(1); // pending 完成，run 检测 stopIntent -> stop save
      await repository.awaitReached(2); // A 正在写 stop save，仍 busy

      // 不变量 5：stop save 期间 busy 为 true，新 generation command 必须被拒。
      expect(container.read(isChatBusyProvider), isTrue);
      await sendMsg('BBB'); // 被 busy guard 拒绝，立即返回
      expect(fakeClient.requestHistory, isEmpty); // B 未发起网络请求
      expect(
        container
            .read(chatSessionsProvider)
            .activeConversation
            .messages
            .any((m) => m.content == 'BBB'),
        isFalse,
      ); // B 的 user message 未追加

      repository.releaseSave(2); // stop save 完成
      await stopAFuture.timeout(defaultTimeout);
      await sendAFuture.timeout(defaultTimeout);

      expect(
        container.read(chatSessionsProvider).generation?.phase,
        ChatGenerationPhase.cancelled,
      );
    });

    // ── 不变量 6：concurrent stop 返回同一 completion，不重复保存 ─────────────────
    test(
      'streaming stop save 被 gate 阻塞时并发两次 stop：只发生一次 terminal save',
      () async {
        repository.gateSave(1); // pending
        repository.gateSave(2); // stop save
        final streamController = StreamController<ChatCompletionChunk>();
        addTearDown(streamController.close);
        fakeClient.enqueueStream(streamController.stream);

        final sendFuture = sendMsg('hello');
        await repository.awaitReached(1);
        repository.releaseSave(1); // pending 完成，进入 streaming
        streamController.add(const ChatCompletionChunk(contentDelta: '部分'));
        await Future<void>.delayed(Duration.zero);

        final stop1 = container
            .read(chatSessionsProvider.notifier)
            .stopStreaming();
        await repository.awaitReached(2); // 第一次 stop 的 save 进入 gate

        final saveCountBefore = repository.saveCallCount;
        // 第二次 stop：幂等，返回同一 completion，不重复入队 stop、不重复 save。
        final stop2 = container
            .read(chatSessionsProvider.notifier)
            .stopStreaming();
        await Future<void>.delayed(Duration.zero);
        expect(repository.saveCallCount, saveCountBefore); // 无新 save

        repository.releaseSave(2);
        await stop1.timeout(defaultTimeout);
        await stop2.timeout(defaultTimeout);
        await sendFuture.timeout(defaultTimeout);

        // pending(1) + 一次 stop save(2)，无第二次 stop save。
        expect(repository.saveCallCount, 2);
      },
    );

    // ── 不变量 7：finalizing 不可取消，stop 不覆盖既定 outcome ───────────────────
    test(
      'attempt completed 到 terminal projection 间 stop：无 cancelled save',
      () async {
        repository.gateSave(1); // pending
        repository.gateSave(2); // terminal success save
        final streamController = StreamController<ChatCompletionChunk>();
        addTearDown(streamController.close);
        fakeClient.enqueueStream(streamController.stream);

        final sendFuture = sendMsg('hello');
        await repository.awaitReached(1);
        repository.releaseSave(1);
        streamController.add(const ChatCompletionChunk(contentDelta: '回复'));
        streamController
            .close(); // onDone -> attempt completed -> terminal save
        await repository.awaitReached(2); // terminal save 进入（finalizing）

        // finalizing 期间 stop：不改 outcome，不触发额外 cancelled save。
        final saveBefore = repository.saveCallCount;
        final stopFuture = container
            .read(chatSessionsProvider.notifier)
            .stopStreaming();
        await Future<void>.delayed(Duration.zero);
        expect(repository.saveCallCount, saveBefore); // 无 cancelled save

        repository.releaseSave(2);
        await stopFuture.timeout(defaultTimeout);
        await sendFuture.timeout(defaultTimeout);
        expect(
          container.read(chatSessionsProvider).generation?.phase,
          ChatGenerationPhase.succeeded,
        );
      },
    );

    test(
      'finalizing stop：等待原 terminal completion，outcome 仍为 success',
      () async {
        repository.gateSave(1);
        final streamController = StreamController<ChatCompletionChunk>();
        addTearDown(streamController.close);
        fakeClient.enqueueStream(streamController.stream);

        final sendFuture = sendMsg('hello');
        await repository.awaitReached(1);
        repository.releaseSave(1);
        streamController.add(const ChatCompletionChunk(contentDelta: '回复'));
        streamController
            .close(); // onDone -> finalizing（无 gate，terminal save 直接完成）
        await Future<void>.delayed(Duration.zero);

        // finalizing 期间 stop：等待原 success 终态完成，不改为 cancelled。
        final stopFuture = container
            .read(chatSessionsProvider.notifier)
            .stopStreaming();
        await stopFuture.timeout(defaultTimeout);
        await sendFuture.timeout(defaultTimeout);

        final state = container.read(chatSessionsProvider);
        expect(state.generation?.phase, ChatGenerationPhase.succeeded);
        expect(state.generation?.outcome, isA<ChatGenerationSuccess>());
      },
    );

    // ── 不变量 2/4：persistence 失败只得到一次 persistenceFailed ─────────────────
    test('pending save 失败：只得到一次 persistenceFailed，不重试不发请求', () async {
      repository.gateSave(1); // pending save
      fakeClient.enqueueChunks(['回复']); // 不应被消费
      final sendFuture = sendMsg('hello');
      await repository.awaitReached(1);
      repository.releaseSave(1, error: Exception('pending 失败'));
      await sendFuture.timeout(defaultTimeout);

      final state = container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.persistenceFailed);
      expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
      expect(fakeClient.requestHistory, isEmpty); // 未发起网络请求
      expect(repository.saveCallCount, 1); // 只一次 save（pending），无重试
    });

    test('terminal success save 失败：不假成功、不重试', () async {
      repository.gateSave(1);
      repository.gateSave(2); // terminal save
      fakeClient.enqueueChunks(['回复内容']);
      final sendFuture = sendMsg('hello');
      await repository.awaitReached(1);
      repository.releaseSave(1);
      await repository.awaitReached(2);
      repository.releaseSave(2, error: Exception('terminal 失败'));
      await sendFuture.timeout(defaultTimeout);

      final state = container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.persistenceFailed);
      expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
      expect(fakeClient.requestHistory.length, 1); // 只一次请求，未重试
    });

    test('stop save 失败：仍完成停止并报 persistence 错误', () async {
      repository.gateSave(1);
      repository.gateSave(2); // stop save
      final streamController = StreamController<ChatCompletionChunk>();
      addTearDown(streamController.close);
      fakeClient.enqueueStream(streamController.stream);
      final sendFuture = sendMsg('hello');
      await repository.awaitReached(1);
      repository.releaseSave(1);
      streamController.add(const ChatCompletionChunk(contentDelta: '部分'));
      await Future<void>.delayed(Duration.zero);
      final stopFuture = container
          .read(chatSessionsProvider.notifier)
          .stopStreaming();
      await repository.awaitReached(2);
      repository.releaseSave(2, error: Exception('stop save 失败'));
      await stopFuture.timeout(defaultTimeout);
      await sendFuture.timeout(defaultTimeout);

      final state = container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.persistenceFailed);
      expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
    });

    // ── 不变量 1/9：旧 run 迟到回调不写新 run state ───────────────────────────
    test('A stop 后迟到 chunk/error/done 不写 B state 或完成 B Future', () async {
      repository.gateSave(1);
      final scA = StreamController<ChatCompletionChunk>();
      addTearDown(scA.close);
      fakeClient.enqueueStream(scA.stream);
      final sendAFuture = sendMsg('AAA');
      await repository.awaitReached(1);
      repository.releaseSave(1);
      scA.add(const ChatCompletionChunk(contentDelta: 'A1'));
      await Future<void>.delayed(Duration.zero);

      // A stop。
      await container.read(chatSessionsProvider.notifier).stopStreaming();
      await sendAFuture;

      // B 发送。
      final scB = StreamController<ChatCompletionChunk>();
      addTearDown(scB.close);
      fakeClient.enqueueStream(scB.stream);
      final sendBFuture = sendMsg('BBB');
      await Future<void>.delayed(Duration.zero);

      // A 的迟到回调：token 失效后必须被丢弃，不污染 B。
      scA.add(const ChatCompletionChunk(contentDelta: 'A-late'));
      scA.addError(StateError('A late error'));
      scA.close();

      // B 正常完成。
      scB.add(const ChatCompletionChunk(contentDelta: 'B-reply'));
      scB.close();
      await sendBFuture.timeout(defaultTimeout);

      final state = container.read(chatSessionsProvider);
      expect(
        state.activeConversation.messages.last.content,
        'B-reply',
      ); // 不含 A-late
      expect(state.generation?.phase, ChatGenerationPhase.succeeded);
    });

    // ── 不变量 8：token 全程稳定，attempt 从 1 开始 ────────────────────────────
    test(
      'preparing/streaming/terminal snapshot 与 outcome identity 一致',
      () async {
        fakeClient.enqueueChunks(['回复']);
        int? preparingId;
        int? preparingAttempt;
        int? streamingId;
        final sub = container.listen<ChatSessionsState>(chatSessionsProvider, (
          previous,
          next,
        ) {
          final phase = next.generation?.phase;
          if (phase == ChatGenerationPhase.preparing && preparingId == null) {
            preparingId = next.generation?.generationId;
            preparingAttempt = next.generation?.attempt;
          } else if (phase == ChatGenerationPhase.streaming &&
              streamingId == null) {
            streamingId = next.generation?.generationId;
          }
        });
        addTearDown(sub.close);

        await sendMsg('hello');

        final state = container.read(chatSessionsProvider);
        expect(preparingId, isNonZero);
        expect(preparingAttempt, 1);
        expect(preparingId, streamingId); // preparing 与 streaming 同一 token
        expect(
          state.generation?.generationId,
          preparingId,
        ); // terminal 仍同一 token
        expect(state.generation?.outcome?.generationId, preparingId);
        expect(state.generation?.attempt, 1); // attempt 从 1 开始
        expect(state.generation?.outcome?.attempt, 1);
      },
    );
  });
}

final _testModel = LlmModelConfig(
  id: 'model-1',
  displayName: 'Test Model',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test',
  modelName: 'test-model',
  supportsReasoning: false,
);
