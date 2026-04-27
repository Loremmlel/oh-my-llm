import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

import '../../../test_database.dart';

Future<SharedPreferences> createSeededPreferences() async {
  SharedPreferences.setMockInitialValues({
    llmModelConfigsStorageKey: jsonEncode([
      {
        'id': 'model-1',
        'displayName': 'GPT-4.1',
        'apiUrl': 'https://api.example.com/v1/chat/completions',
        'apiKey': 'sk-test-12345678',
        'modelName': 'gpt-4.1',
        'supportsReasoning': true,
      },
    ]),
    promptTemplatesStorageKey: jsonEncode([
      {
        'id': 'prompt-1',
        'name': '代码助手',
        'systemPrompt': '你是代码助手',
        'messages': [
          {'id': 'message-1', 'role': 'user', 'content': '请优先关注实现细节。'},
        ],
        'updatedAt': DateTime(2026, 4, 26).toIso8601String(),
      },
    ]),
    fixedPromptSequencesStorageKey: jsonEncode({
      'version': VersionedJsonStorage.currentSchemaVersion,
      'items': [
        {
          'id': 'sequence-1',
          'name': '对比测试流程',
          'steps': [
            {'id': 'step-1', 'content': '请先总结当前实现的核心目标。'},
            {'id': 'step-2', 'content': '请列出三个可执行方案，并说明权衡。'},
          ],
          'updatedAt': DateTime(2026, 4, 27).toIso8601String(),
        },
      ],
    }),
  });

  return SharedPreferences.getInstance();
}

Future<void> pumpChatScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required FakeChatCompletionClient fakeClient,
  Size size = const Size(1440, 1600),
}) async {
  final database = await createTestDatabase(preferences);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    database.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );

  await tester.pumpAndSettle();
}

Future<void> sendMessage(WidgetTester tester, String content) async {
  await tester.enterText(find.byType(TextField).first, content);
  final sendButton = find.widgetWithText(FilledButton, '发送');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await tester.pump();
}

class FakeChatCompletionClient implements ChatCompletionClient {
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
