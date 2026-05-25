import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

/// 创建包含聊天页所需种子数据的 SharedPreferences。
Future<SharedPreferences> createSeededPreferences() async {
  return TestFixtures.seedPreferences(
    models: [TestFixtures.gpt41()],
    prompts: [TestFixtures.codeAssistantPrompt()],
    sequences: [
      TestFixtures.fixedSequence(
        id: 'sequence-1',
        name: '对比测试流程',
        steps: [
          TestFixtures.sequenceStep(
            id: 'step-1',
            content: '请先总结当前实现的核心目标。',
          ),
          TestFixtures.sequenceStep(
            id: 'step-2',
            content: '请列出三个可执行方案，并说明权衡。',
          ),
        ],
        updatedAt: DateTime(2026, 4, 27),
      ),
    ],
  );
}

/// 挂载 ChatScreen 到标准测试环境并返回数据库实例。
Future<AppDatabase> pumpChatScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required FakeChatCompletionClient fakeClient,
  Size size = const Size(1440, 1600),
}) async {
  return pumpTestApp(
    tester,
    child: const ChatScreen(),
    preferences: preferences,
    viewportSize: size,
    extraOverrides: [
      chatCompletionClientProvider.overrideWithValue(fakeClient),
    ],
  );
}

/// 在聊天输入框中填入内容并点击发送按钮。
Future<void> sendMessage(WidgetTester tester, String content) async {
  await tester.enterText(
    find.byKey(const ValueKey('chat-message-composer')),
    content,
  );
  final sendButton = find.widgetWithText(FilledButton, '发送');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await tester.pump();
}

class FakeChatCompletionClient extends ChatCompletionClient {
  final List<List<ChatCompletionRequestMessage>> requestHistory = [];
  final List<LlmModelConfig> requestedModels = [];
  final List<Stream<ChatCompletionChunk>> _queuedStreams = [];
  List<ChatCompletionRequestMessage> lastRequestMessages = const [];
  LlmModelConfig? lastModelConfig;

  @override
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) {
    lastModelConfig = modelConfig;
    lastRequestMessages = List.unmodifiable(messages);
    requestHistory.add(lastRequestMessages);
    requestedModels.add(modelConfig);
    if (_queuedStreams.isEmpty) {
      return const Stream<ChatCompletionChunk>.empty();
    }

    return _queuedStreams.removeAt(0);
  }

  void enqueueError(Object error) {
    _queuedStreams.add(Stream<ChatCompletionChunk>.error(error));
  }

  void enqueueStream(Stream<ChatCompletionChunk> stream) {
    _queuedStreams.add(stream);
  }

  void enqueueChunks(
    List<String> chunks, {
    Duration chunkDelay = Duration.zero,
  }) {
    _queuedStreams.add(
      _streamDeltas(
        chunks
            .map((chunk) => ChatCompletionChunk(contentDelta: chunk))
            .toList(growable: false),
        chunkDelay,
      ),
    );
  }

  void enqueueDeltas(
    List<ChatCompletionChunk> chunks, {
    Duration chunkDelay = Duration.zero,
  }) {
    _queuedStreams.add(_streamDeltas(chunks, chunkDelay));
  }

  Stream<ChatCompletionChunk> _streamDeltas(
    List<ChatCompletionChunk> chunks,
    Duration chunkDelay,
  ) async* {
    for (final chunk in chunks) {
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
      yield chunk;
    }
  }
}
