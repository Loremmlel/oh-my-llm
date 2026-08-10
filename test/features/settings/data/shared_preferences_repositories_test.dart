import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/chat_defaults.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

void main() {
  group('ChatDefaultsRepository', () {
    test('empty storage returns defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      expect(ChatDefaultsRepository(preferences).load(), const ChatDefaults());
    });

    test('save and load preserve both selections', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = ChatDefaultsRepository(preferences);
      const original = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: 'preset-1',
      );

      await repository.save(original);

      expect(repository.load(), original);
    });

    test('a non-object payload falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        chatDefaultsStorageKey: jsonEncode([1, 2, 3]),
      });
      final preferences = await SharedPreferences.getInstance();

      expect(ChatDefaultsRepository(preferences).load(), const ChatDefaults());
    });
  });

  group('LlmModelConfigRepository', () {
    test('missing and empty storage return empty lists', () async {
      for (final testCase in [
        (name: 'missing', values: <String, Object>{}),
        (
          name: 'empty string',
          values: <String, Object>{llmModelConfigsStorageKey: ''},
        ),
      ]) {
        SharedPreferences.setMockInitialValues(testCase.values);
        final preferences = await SharedPreferences.getInstance();
        final repository = LlmModelConfigRepository(preferences);

        expect(repository.loadProviders(), isEmpty, reason: testCase.name);
        expect(repository.loadAll(), isEmpty, reason: testCase.name);
      }
    });

    test(
      'provider round-trip restores provider context on resolved models',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final repository = LlmModelConfigRepository(preferences);
        const providers = [
          LlmProviderConfig(
            id: 'provider-1',
            name: 'OpenAI 官方',
            apiUrl: 'https://api.openai.com/v1/chat/completions',
            apiKey: 'sk-secret',
            apiProtocol: LlmApiProtocol.chatCompletions,
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'GPT-4.1',
                modelName: 'gpt-4.1',
                supportsReasoning: true,
              ),
              LlmProviderModelConfig(
                id: 'model-2',
                displayName: 'GPT-4o mini',
                modelName: 'gpt-4o-mini',
                supportsReasoning: false,
              ),
            ],
          ),
        ];

        await repository.saveProviders(providers);

        expect(repository.loadProviders(), providers);
        final models = repository.loadAll();
        expect(models.map((model) => model.id), ['model-1', 'model-2']);
        expect(
          models.every((model) => model.providerId == 'provider-1'),
          isTrue,
        );
      },
    );

    test('a rejected write is reported to the caller', () async {
      const repository = LlmModelConfigRepository.fromStore(
        _RejectingSettingsKeyValueStore(),
      );

      await expectLater(
        repository.saveProviders(const []),
        throwsA(isA<StateError>()),
      );
    });
  });
}

final class _RejectingSettingsKeyValueStore implements SettingsKeyValueStore {
  const _RejectingSettingsKeyValueStore();

  @override
  String? getString(String key) => null;

  @override
  int? getInt(String key) => null;

  @override
  Future<bool> setInt(String key, int value) async => false;

  @override
  Future<bool> setString(String key, String value) async => false;
}
