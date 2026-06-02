import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

/// 类型安全的测试数据工厂。
///
/// 所有工厂方法返回真实的 Dart 模型对象，确保编译期类型检查。
/// 需要 JSON 格式时通过模型自带的 [toJson] 方法转换。
class TestFixtures {
  TestFixtures._();

  // ── 模型配置 ──────────────────────────────────────────────

  static LlmModelConfig model({
    String id = 'model-1',
    String displayName = 'Test Model',
    String modelName = 'test-model',
    bool supportsReasoning = false,
    String apiUrl = 'https://api.example.com/v1/chat/completions',
    String apiKey = 'sk-test',
    String providerId = '',
    String providerName = '',
  }) =>
      LlmModelConfig(
        id: id,
        displayName: displayName,
        apiUrl: apiUrl,
        apiKey: apiKey,
        modelName: modelName,
        supportsReasoning: supportsReasoning,
        providerId: providerId,
        providerName: providerName,
      );

  static LlmModelConfig gpt41() => model(
        id: 'model-gpt',
        displayName: 'GPT-4.1',
        modelName: 'gpt-4.1',
        supportsReasoning: true,
      );

  static LlmModelConfig claudeSonnet() => model(
        id: 'model-claude',
        displayName: 'Claude Sonnet',
        modelName: 'claude-sonnet',
        supportsReasoning: false,
      );

  static LlmModelConfig deepSeekV4() => model(
        id: 'model-deepseek',
        displayName: 'DeepSeek V4 Flash',
        modelName: 'deepseek-v4-flash',
        supportsReasoning: true,
      );

  // ── 预设提示词 ────────────────────────────────────────────

  static PromptMessage promptMessage({
    required String id,
    PromptMessageRole role = PromptMessageRole.user,
    String content = '测试消息',
    String title = '',
    PromptMessagePlacement placement = PromptMessagePlacement.before,
  }) =>
      PromptMessage(
        id: id,
        role: role,
        content: content,
        title: title,
        placement: placement,
      );

  static PresetPrompt presetPrompt({
    required String id,
    String name = '测试提示词',
    List<PromptMessage> messages = const [],
    DateTime? updatedAt,
  }) =>
      PresetPrompt(
        id: id,
        name: name,
        messages: messages,
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
      );

  static PresetPrompt codeAssistantPrompt() => presetPrompt(
        id: 'prompt-1',
        name: '代码助手',
        messages: [
          promptMessage(
            id: 'message-1',
            role: PromptMessageRole.user,
            content: '请优先关注实现细节。',
          ),
        ],
        updatedAt: DateTime(2026, 4, 26),
      );

  // ── 聊天消息 ──────────────────────────────────────────────

  static ChatMessage userMessage({
    required String id,
    String content = '你好',
    DateTime? createdAt,
    String? parentId,
  }) =>
      ChatMessage(
        id: id,
        role: ChatMessageRole.user,
        content: content,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        parentId: parentId,
      );

  static ChatMessage assistantMessage({
    required String id,
    String content = '你好，有什么可以帮助你的？',
    String reasoningContent = '',
    String assistantModelDisplayName = '匿名模型',
    DateTime? createdAt,
    String? parentId,
  }) =>
      ChatMessage(
        id: id,
        role: ChatMessageRole.assistant,
        content: content,
        reasoningContent: reasoningContent,
        assistantModelDisplayName: assistantModelDisplayName,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        parentId: parentId,
      );

  // ── 流式补全 ──────────────────────────────────────────────

  static ChatCompletionChunk contentChunk(String delta) =>
      ChatCompletionChunk(contentDelta: delta);

  static ChatCompletionChunk reasoningChunk(String delta) =>
      ChatCompletionChunk(reasoningDelta: delta);

  // ── 固定提示词序列 ────────────────────────────────────────

  static FixedPromptSequenceStep sequenceStep({
    required String id,
    String content = '步骤内容',
    String title = '',
  }) =>
      FixedPromptSequenceStep(id: id, content: content, title: title);

  static FixedPromptSequence fixedSequence({
    required String id,
    String name = '测试序列',
    List<FixedPromptSequenceStep> steps = const [],
    DateTime? updatedAt,
  }) =>
      FixedPromptSequence(
        id: id,
        name: name,
        steps: steps,
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
      );

  // ── 模板提示词 ────────────────────────────────────────────

  static TemplatePromptVariable templateVariable({
    required String name,
    String defaultValue = '',
  }) =>
      TemplatePromptVariable(name: name, defaultValue: defaultValue);

  static TemplatePrompt templatePrompt({
    required String id,
    String title = '测试模板',
    String content = '请处理{{正文}}',
    List<TemplatePromptVariable> variables = const [],
    DateTime? updatedAt,
  }) =>
      TemplatePrompt(
        id: id,
        title: title,
        content: content,
        variables: variables,
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
      );

  // ── 记忆提示词 ────────────────────────────────────────────

  static MemoryPrompt memoryPrompt({
    required String id,
    String name = '测试记忆',
    String content = '请总结当前对话的关键事实与待办。',
    DateTime? updatedAt,
  }) =>
      MemoryPrompt(
        id: id,
        name: name,
        content: content,
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
      );

  // ── 批量种子 SharedPreferences ────────────────────────────

  /// 将模型配置和提示词数据写入 SharedPreferences mock 与 SQLite。
  ///
  /// [database] 用于通过 Repository API 写入 SQLite（预设提示词、固定序列、聊天会话）。
  /// 服务商模型配置和聊天默认值仍写入 SharedPreferences。
  static Future<SharedPreferences> seedPreferences({
    required AppDatabase database,
    List<LlmModelConfig> models = const [],
    List<PresetPrompt> prompts = const [],
    Map<String, dynamic>? chatDefaults,
    List<FixedPromptSequence> sequences = const [],
    List<Map<String, dynamic>> conversations = const [],
  }) async {
    // ── SQLite 写入（通过 Repository API） ──────────────────

    if (prompts.isNotEmpty) {
      await presetPromptRepository.saveAll(database, prompts);
    }

    if (sequences.isNotEmpty) {
      await fixedPromptSequenceRepository.saveAll(database, sequences);
    }

    if (conversations.isNotEmpty) {
      await SqliteChatConversationRepository(database).saveConversations(
        conversations
            .map((c) => ChatConversation.fromJson(c))
            .toList(growable: false),
      );
    }

    // ── SharedPreferences 写入（服务商配置 + 聊天默认值） ────

    final values = <String, String>{};

    if (models.isNotEmpty) {
      final providerMap = <String, List<LlmModelConfig>>{};
      for (final m in models) {
        final key = '${m.apiUrl}||${m.apiKey}';
        providerMap.putIfAbsent(key, () => []).add(m);
      }
      final providers = providerMap.entries.map((entry) {
        final group = entry.value;
        final first = group.first;
        return LlmProviderConfig(
          id: first.providerId.isEmpty ? 'provider-${first.id}' : first.providerId,
          name: first.providerName.isEmpty ? first.displayName : first.providerName,
          apiUrl: first.apiUrl,
          apiKey: first.apiKey,
          models: group
              .map((m) => LlmProviderModelConfig(
                    id: m.id,
                    displayName: m.displayName,
                    modelName: m.modelName,
                    supportsReasoning: m.supportsReasoning,
                  ))
              .toList(growable: false),
        );
      }).toList(growable: false);
      values[llmModelConfigsStorageKey] = VersionedJsonStorage.encodeObjectList(
        items: providers,
        toJson: (p) => p.toJson(),
      );
    }

    if (chatDefaults != null) {
      values[chatDefaultsStorageKey] = jsonEncode(chatDefaults);
    }

    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }
}
