import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_provider_import_merger.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

LlmProviderModelConfig _model({
  String id = 'model-1',
  String displayName = 'GPT-4',
  String modelName = 'gpt-4',
  bool supportsReasoning = false,
}) {
  return LlmProviderModelConfig(
    id: id,
    displayName: displayName,
    modelName: modelName,
    supportsReasoning: supportsReasoning,
  );
}

LlmProviderConfig _provider({
  String id = 'provider-1',
  String name = 'OpenAI',
  String apiUrl = 'https://api.openai.com/v1/chat/completions',
  String apiKey = 'sk-test',
  LlmApiProtocol apiProtocol = LlmApiProtocol.chatCompletions,
  List<LlmProviderModelConfig>? models,
}) {
  return LlmProviderConfig(
    id: id,
    name: name,
    apiUrl: apiUrl,
    apiKey: apiKey,
    apiProtocol: apiProtocol,
    models: models ?? [],
  );
}

void main() {
  group('mergeImportedLlmProviders', () {
    test('同 ID 时传入字段覆盖本地字段并按模型名合并', () {
      final result = mergeImportedLlmProviders(
        local: [
          _provider(
            name: '旧服务商',
            apiUrl: 'https://old.example.com/v1',
            apiKey: 'old-key',
            models: [_model(id: 'local-model', modelName: 'shared-model')],
          ),
        ],
        incoming: [
          _provider(
            name: '新服务商',
            apiUrl: 'https://new.example.com/v1',
            apiKey: 'new-key',
            apiProtocol: LlmApiProtocol.responses,
            models: [
              _model(id: 'duplicate', modelName: 'shared-model'),
              _model(id: 'new-model', modelName: 'new-model'),
            ],
          ),
        ],
      );

      final provider = result.single;
      expect(provider.name, '新服务商');
      expect(provider.apiUrl, 'https://new.example.com/v1');
      expect(provider.apiKey, 'new-key');
      expect(provider.apiProtocol, LlmApiProtocol.responses);
      expect(provider.models.map((model) => model.modelName).toSet(), {
        'shared-model',
        'new-model',
      });
      expect(
        provider.models
            .firstWhere((model) => model.modelName == 'shared-model')
            .id,
        'local-model',
      );
    });

    test('等价键匹配时保留本地身份并合并新模型', () {
      final result = mergeImportedLlmProviders(
        local: [
          _provider(
            id: 'local-provider',
            name: '本地服务商',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            models: [_model(modelName: 'local-model')],
          ),
        ],
        incoming: [
          _provider(
            id: 'incoming-provider',
            name: '传入服务商',
            apiUrl: 'https://same.example.com/v1/chat/completions',
            apiKey: 'same-key',
            models: [_model(id: 'incoming-model', modelName: 'new-model')],
          ),
        ],
      );

      expect(result.single.id, 'local-provider');
      expect(result.single.name, '本地服务商');
      expect(result.single.models.map((model) => model.modelName).toSet(), {
        'local-model',
        'new-model',
      });
    });

    test('相同 URL 与密钥但协议不同时保留两个服务商', () {
      final result = mergeImportedLlmProviders(
        local: [
          _provider(
            id: 'chat-provider',
            apiUrl: 'https://same.example.com/v1',
            apiKey: 'same-key',
          ),
        ],
        incoming: [
          _provider(
            id: 'responses-provider',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            apiProtocol: LlmApiProtocol.responses,
          ),
        ],
      );

      expect(result.map((provider) => provider.apiProtocol).toSet(), {
        LlmApiProtocol.chatCompletions,
        LlmApiProtocol.responses,
      });
    });

    test('等价键匹配时重复模型名只保留首个模型', () {
      final result = mergeImportedLlmProviders(
        local: [
          _provider(
            id: 'local-provider',
            apiUrl: 'https://same.example.com/v1',
            apiKey: 'same-key',
            models: [_model(id: 'local-model', modelName: 'same-model')],
          ),
        ],
        incoming: [
          _provider(
            id: 'incoming-provider',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            models: [
              _model(id: 'duplicate-model', modelName: 'same-model'),
              _model(id: 'new-first', modelName: 'new-model'),
              _model(id: 'new-duplicate', modelName: 'new-model'),
            ],
          ),
        ],
      );

      expect(result.single.models, hasLength(2));
      expect(
        result.single.models
            .firstWhere((model) => model.modelName == 'new-model')
            .id,
        'new-first',
      );
    });
  });

  group('LlmProviderConfigsController', () {
    late SharedPreferences preferences;
    late ProviderContainer container;
    late LlmProviderConfigsController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          llmModelConfigRepositoryProvider.overrideWithValue(
            LlmModelConfigRepository(preferences),
          ),
        ],
      );
      controller = container.read(llmProviderConfigsProvider.notifier);
    });

    tearDown(() => container.dispose());

    List<LlmProviderConfig> readPersisted() {
      final revived = ProviderContainer(
        overrides: [
          llmModelConfigRepositoryProvider.overrideWithValue(
            LlmModelConfigRepository(preferences),
          ),
        ],
      );
      final state = revived.read(llmProviderConfigsProvider);
      revived.dispose();
      return state;
    }

    test('服务商增删改会排序并持久化最终状态', () async {
      expect(container.read(llmProviderConfigsProvider), isEmpty);
      await controller.upsertProvider(_provider(id: 'p-2', name: 'Charlie'));
      await controller.upsertProvider(_provider(id: 'p-1', name: 'Alpha'));
      await controller.upsertProvider(
        _provider(
          id: 'p-2',
          name: 'Bravo',
          apiUrl: 'https://updated.example.com',
        ),
      );

      expect(
        container
            .read(llmProviderConfigsProvider)
            .map((provider) => provider.name),
        ['Alpha', 'Bravo'],
      );
      await controller.deleteProviderById('p-1');

      final persisted = readPersisted();
      expect(persisted, hasLength(1));
      expect(persisted.single.id, 'p-2');
      expect(persisted.single.apiUrl, 'https://updated.example.com');
    });

    test('批量写入可同时更新既有服务商并新增服务商', () async {
      await controller.upsertProvider(_provider(id: 'p-1', name: '旧名称'));

      await controller.upsertAllProviders([
        _provider(id: 'p-1', name: '新名称'),
        _provider(id: 'p-2', name: '新增服务商'),
      ]);

      final persisted = readPersisted();
      expect(persisted, hasLength(2));
      expect(persisted.firstWhere((item) => item.id == 'p-1').name, '新名称');
      expect(persisted.firstWhere((item) => item.id == 'p-2').name, '新增服务商');
    });

    test('导入合并采用纯函数契约并持久化结果', () async {
      await controller.upsertProvider(
        _provider(
          id: 'local',
          name: '本地服务商',
          apiUrl: 'https://same.example.com',
          apiKey: 'same-key',
          models: [_model(id: 'local-model', modelName: 'model-a')],
        ),
      );

      await controller.mergeImportedProviders([
        _provider(
          id: 'incoming',
          name: '传入服务商',
          apiUrl: 'https://same.example.com/v1/chat/completions',
          apiKey: 'same-key',
          models: [_model(id: 'incoming-model', modelName: 'model-b')],
        ),
      ]);

      final persisted = readPersisted();
      expect(persisted, hasLength(1));
      expect(persisted.single.id, 'local');
      expect(persisted.single.models.map((model) => model.modelName).toSet(), {
        'model-a',
        'model-b',
      });
    });

    test('导入持久化失败时不发布新状态', () async {
      final seed = _provider(
        id: 'seed-provider',
        name: '种子服务商',
        models: [_model(modelName: 'seed-model')],
      );
      final storage = _ReadableSettingsKeyValueStore(
        readableValues: {
          llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
            items: [seed],
            toJson: (provider) => provider.toJson(),
          ),
        },
      );
      final failingContainer = ProviderContainer(
        overrides: [
          llmModelConfigRepositoryProvider.overrideWithValue(
            LlmModelConfigRepository.fromStore(storage),
          ),
        ],
      );
      addTearDown(failingContainer.dispose);
      final failingController = failingContainer.read(
        llmProviderConfigsProvider.notifier,
      );

      await expectLater(
        failingController.mergeImportedProviders([
          _provider(id: 'incoming-provider'),
        ]),
        throwsA(isA<StateError>()),
      );
      expect(failingController.state, [seed]);
    });

    test('单模型增改删会持久化最终状态', () async {
      await controller.upsertProvider(
        _provider(
          id: 'p-1',
          models: [_model(id: 'm-1', modelName: 'old-model')],
        ),
      );
      await controller.upsertModel(
        providerId: 'p-1',
        model: _model(id: 'm-2', modelName: 'new-model'),
      );
      await controller.upsertModel(
        providerId: 'p-1',
        model: _model(
          id: 'm-2',
          displayName: '已更新',
          modelName: 'updated-model',
        ),
      );
      await controller.deleteModel(providerId: 'p-1', modelId: 'm-1');

      final models = readPersisted().single.models;
      expect(models, hasLength(1));
      expect(models.single.id, 'm-2');
      expect(models.single.displayName, '已更新');
    });

    test('批量模型按 modelName 去重并返回净增量', () async {
      await controller.upsertProvider(
        _provider(
          id: 'p-1',
          models: [_model(id: 'existing', modelName: 'shared')],
        ),
      );

      final addedCount = await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _model(id: 'duplicate-existing', modelName: 'shared'),
          _model(id: 'new-first', modelName: 'new-model'),
          _model(id: 'new-duplicate', modelName: 'new-model'),
        ],
      );

      expect(addedCount, 1);
      expect(readPersisted().single.models.map((model) => model.id).toList(), [
        'existing',
        'new-first',
      ]);
    });
  });
}

final class _ReadableSettingsKeyValueStore implements SettingsKeyValueStore {
  _ReadableSettingsKeyValueStore({required this.readableValues});

  final Map<String, String> readableValues;

  @override
  String? getString(String key) => readableValues[key];

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  int? getInt(String key) => null;

  @override
  Future<bool> setInt(String key, int value) async => false;
}
