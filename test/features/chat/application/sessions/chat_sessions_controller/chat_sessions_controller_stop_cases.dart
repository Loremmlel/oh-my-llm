import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../../../../helpers/async/async_test_signals.dart';
import '../../../../../helpers/chat/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// controller 与 generation lifecycle 之间的 stop / dispose 集成契约。
///
/// 各阶段 stop、并发 stop、迟到事件与终态状态机由 generation 层的专门测试覆盖；
/// 此处只保留跨 controller、持久化和 Riverpod 生命周期的代表性路径。
void registerChatSessionsControllerStopCases() {
  late ControllerTestHarness harness;
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatGenerationClient fakeClient;
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

  Future<void> sendMsg(String content) => harness.sendMsg(content);

  test('stopStreaming 保留部分回复并投影用户取消终态', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);

    final sendFuture = sendMsg('请开始生成');
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(contentDelta: '部分回复'));
    await harness.waitForState(
      (state) => state.streamingReply?.content == '部分回复',
      description: '流式内容达到期望片段',
    );

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.last.content, '部分回复');
    expect(state.activeConversation.messages.last.isStreaming, isFalse);
    expect(state.generation?.phase, ChatGenerationPhase.cancelled);
    expect(state.generation?.cancelReason, ChatCancelReason.userStop);
    expect(state.generation?.outcome, isA<ChatGenerationCancelled>());
  });

  test('stopStreaming 在 cancel 挂起时仍能一次终止', () async {
    final listened = Completer<void>();
    final streamController = StreamController<ChatGenerationChunk>(
      onListen: listened.complete,
      onCancel: () => Completer<void>().future,
    );
    addTearDown(() => streamController.onCancel = null);
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试挂起 cancel');
    await listened.future;
    streamController.add(const ChatGenerationChunk(contentDelta: '部分内容'));
    await harness.waitForState(
      (state) => state.streamingReply?.content == '部分内容',
      description: '流式内容达到期望片段',
    );

    await container
        .read(chatSessionsProvider.notifier)
        .stopStreaming()
        .timeout(const Duration(seconds: 2));
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages.last.content, '部分内容');
  });

  test('streaming stop 落盘失败投影 persistenceFailed', () async {
    final repository = _FailingStopSaveRepository(
      SqliteChatConversationRepository(database),
    );
    final stopContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(stopContainer.dispose);

    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final sendFuture = stopContainer
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '测试 stop 落盘失败',
          modelConfig: testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(contentDelta: '部分内容'));
    await waitForProviderState(
      container: stopContainer,
      provider: chatSessionsProvider,
      matches: (state) => state.streamingReply?.content == '部分内容',
      description: '流式内容达到期望片段',
    );

    await stopContainer.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture.timeout(const Duration(seconds: 5));

    final state = stopContainer.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.generation?.phase, ChatGenerationPhase.persistenceFailed);
    expect(state.generation?.outcome, isA<ChatGenerationPersistenceFailure>());
    expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
  });

  test('dispose 在流式进行时结束发送且丢弃迟到事件', () async {
    final disposeContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(
          SqliteChatConversationRepository(database),
        ),
      ],
    );
    var disposed = false;
    addTearDown(() {
      if (!disposed) disposeContainer.dispose();
    });

    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
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
      await controlled.listened;
      controlled.add(const ChatGenerationChunk(contentDelta: '部分'));
      await waitForProviderState(
        container: disposeContainer,
        provider: chatSessionsProvider,
        matches: (state) => state.streamingReply?.content == '部分',
        description: '流式内容达到期望片段',
      );

      disposeContainer.dispose();
      disposed = true;
      await sendFuture.timeout(const Duration(seconds: 2));
      controlled.add(const ChatGenerationChunk(contentDelta: '迟到'));
      await controlled.close();
    }, (error, stack) => unexpected.add(error));

    expect(unexpected, isEmpty);
  });
}

class _FailingStopSaveRepository implements ChatConversationRepository {
  _FailingStopSaveRepository(this._inner);

  final ChatConversationRepository _inner;
  int _saveCount = 0;

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    _saveCount++;
    if (_saveCount == 2) {
      throw StateError('模拟 stop 落盘失败');
    }
    await _inner.saveConversation(conversation);
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) =>
      _inner.saveConversations(conversations);

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
