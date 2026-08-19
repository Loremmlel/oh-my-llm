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

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderModelConfig _modelConfig({
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

LlmProviderConfig _providerConfig({
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
    test('同 ID 时传入服务商字段替换本地字段并按模型名合并', () {
      final result = mergeImportedLlmProviders(
        local: [
          _providerConfig(
            id: 'provider-1',
            name: '旧服务商',
            apiUrl: 'https://old.example.com/v1',
            apiKey: 'old-key',
            apiProtocol: LlmApiProtocol.chatCompletions,
            models: [
              _modelConfig(
                id: 'local-model',
                displayName: '本地模型',
                modelName: 'shared-model',
              ),
            ],
          ),
        ],
        incoming: [
          _providerConfig(
            id: 'provider-1',
            name: '新服务商',
            apiUrl: 'https://new.example.com/v1',
            apiKey: 'new-key',
            apiProtocol: LlmApiProtocol.responses,
            models: [
              _modelConfig(
                id: 'incoming-duplicate',
                displayName: '传入重复模型',
                modelName: 'shared-model',
              ),
              _modelConfig(
                id: 'incoming-new',
                displayName: '传入新模型',
                modelName: 'new-model',
              ),
            ],
          ),
        ],
      );

      expect(result, hasLength(1));
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

    test('等价键匹配时保留本地服务商身份并合并新模型', () {
      final result = mergeImportedLlmProviders(
        local: [
          _providerConfig(
            id: 'local-provider',
            name: '本地服务商',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            models: [_modelConfig(modelName: 'local-model')],
          ),
        ],
        incoming: [
          _providerConfig(
            id: 'incoming-provider',
            name: '传入服务商',
            apiUrl: 'https://same.example.com/v1/chat/completions',
            apiKey: 'same-key',
            models: [
              _modelConfig(id: 'incoming-model', modelName: 'new-model'),
            ],
          ),
        ],
      );

      expect(result, hasLength(1));
      expect(result.single.id, 'local-provider');
      expect(result.single.name, '本地服务商');
      expect(result.single.apiUrl, 'https://same.example.com');
      expect(result.single.models.map((model) => model.modelName).toSet(), {
        'local-model',
        'new-model',
      });
    });

    test('相同 URL 与密钥但协议不同时保留两个服务商', () {
      final result = mergeImportedLlmProviders(
        local: [
          _providerConfig(
            id: 'chat-provider',
            name: 'Chat',
            apiUrl: 'https://same.example.com/v1',
            apiKey: 'same-key',
            apiProtocol: LlmApiProtocol.chatCompletions,
          ),
        ],
        incoming: [
          _providerConfig(
            id: 'responses-provider',
            name: 'Responses',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            apiProtocol: LlmApiProtocol.responses,
          ),
        ],
      );

      expect(result, hasLength(2));
      expect(result.map((provider) => provider.apiProtocol).toSet(), {
        LlmApiProtocol.chatCompletions,
        LlmApiProtocol.responses,
      });
    });

    test('等价键匹配时重复模型名只保留一个模型', () {
      final result = mergeImportedLlmProviders(
        local: [
          _providerConfig(
            id: 'local-provider',
            apiUrl: 'https://same.example.com/v1',
            apiKey: 'same-key',
            models: [
              _modelConfig(
                id: 'local-model',
                displayName: '本地模型',
                modelName: 'same-model',
              ),
            ],
          ),
        ],
        incoming: [
          _providerConfig(
            id: 'incoming-provider',
            apiUrl: 'https://same.example.com',
            apiKey: 'same-key',
            models: [
              _modelConfig(
                id: 'duplicate-model',
                displayName: '重复模型',
                modelName: 'same-model',
              ),
              _modelConfig(
                id: 'new-model-first',
                displayName: '新模型',
                modelName: 'new-model',
              ),
              _modelConfig(
                id: 'new-model-duplicate',
                displayName: '新模型重复',
                modelName: 'new-model',
              ),
            ],
          ),
        ],
      );

      final models = result.single.models;
      expect(models, hasLength(2));
      expect(models.map((model) => model.modelName).toSet(), {
        'same-model',
        'new-model',
      });
      expect(
        models.firstWhere((model) => model.modelName == 'new-model').id,
        'new-model-first',
      );
    });
  });

  group('LlmProviderConfigsController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late LlmProviderConfigsController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          llmModelConfigRepositoryProvider.overrideWithValue(
            LlmModelConfigRepository(sp),
          ),
        ],
      );
      controller = container.read(llmProviderConfigsProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    // 辅助：创建新 container 验证持久化（从同一 SharedPreferences 实例读取）
    List<LlmProviderConfig> readPersisted() {
      final verifyContainer = ProviderContainer(
        overrides: [
          llmModelConfigRepositoryProvider.overrideWithValue(
            LlmModelConfigRepository(sp),
          ),
        ],
      );
      final state = verifyContainer.read(llmProviderConfigsProvider);
      verifyContainer.dispose();
      return state;
    }

    // ── build() ─────────────────────────────────────────────────────────────

    test('build() returns empty list when no stored data', () {
      final state = container.read(llmProviderConfigsProvider);
      expect(state, isEmpty);
    });

    // ── upsertProvider() ────────────────────────────────────────────────────

    test('upsertProvider() adds a new provider', () async {
      final provider = _providerConfig(id: 'p-1', name: 'OpenAI');

      await controller.upsertProvider(provider);

      final state = container.read(llmProviderConfigsProvider);
      expect(state.length, 1);
      expect(state.first.id, 'p-1');
      expect(state.first.name, 'OpenAI');

      // 验证持久化
      expect(readPersisted().length, 1);
    });

    test('upsertProvider() updates existing provider by id', () async {
      final original = _providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1',
        models: [_modelConfig(id: 'm-1', displayName: 'GPT-4')],
      );
      await controller.upsertProvider(original);

      // 更新同名 provider
      final updated = _providerConfig(
        id: 'p-1',
        name: 'OpenAI-Updated',
        apiUrl: 'https://api.openai.com/v2',
        models: [_modelConfig(id: 'm-2', displayName: 'GPT-4o')],
      );
      await controller.upsertProvider(updated);

      final state = container.read(llmProviderConfigsProvider);
      expect(state.length, 1);
      expect(state.first.id, 'p-1');
      expect(state.first.name, 'OpenAI-Updated');
      expect(state.first.apiUrl, 'https://api.openai.com/v2');
      expect(state.first.models.length, 1);
      expect(state.first.models.first.id, 'm-2');

      // 验证持久化：新容器读到更新后的数据
      final persisted = readPersisted();
      expect(persisted.first.name, 'OpenAI-Updated');
    });

    test('upsertProvider() sorts providers alphabetically by name', () async {
      await controller.upsertProvider(
        _providerConfig(id: 'p-3', name: 'Charlie'),
      );
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'Alpha'),
      );
      await controller.upsertProvider(
        _providerConfig(id: 'p-2', name: 'Bravo'),
      );

      final names = container
          .read(llmProviderConfigsProvider)
          .map((p) => p.name)
          .toList();
      expect(names, ['Alpha', 'Bravo', 'Charlie']);
    });

    // ── upsertAllProviders() ────────────────────────────────────────────────

    test('upsertAllProviders() adds multiple new providers', () async {
      await controller.upsertAllProviders([
        _providerConfig(id: 'p-2', name: 'Beta'),
        _providerConfig(id: 'p-1', name: 'Alpha'),
      ]);

      final names = container
          .read(llmProviderConfigsProvider)
          .map((p) => p.name)
          .toList();
      expect(names, ['Alpha', 'Beta']);
      expect(readPersisted().length, 2);
    });

    test(
      'upsertAllProviders() updates existing and adds new in one call',
      () async {
        // 先添加一个已存在的
        await controller.upsertProvider(
          _providerConfig(
            id: 'p-1',
            name: 'Old Name',
            apiUrl: 'https://old.url',
          ),
        );

        // 批量调用：更新 p-1 + 新增 p-2
        await controller.upsertAllProviders([
          _providerConfig(
            id: 'p-1',
            name: 'New Name',
            apiUrl: 'https://new.url',
          ),
          _providerConfig(id: 'p-2', name: 'Brand New'),
        ]);

        final state = container.read(llmProviderConfigsProvider);
        expect(state.length, 2);
        expect(state.firstWhere((p) => p.id == 'p-1').name, 'New Name');
        expect(state.firstWhere((p) => p.id == 'p-2').name, 'Brand New');
        expect(readPersisted().length, 2);
      },
    );

    // ── mergeImportedProviders() ────────────────────────────────────────────

    test('mergeImportedProviders() adds new provider', () async {
      await controller.mergeImportedProviders([
        _providerConfig(id: 'p-1', name: 'Imported'),
      ]);

      expect(container.read(llmProviderConfigsProvider).length, 1);
    });

    test(
      'mergeImportedProviders() merges models for same API URL+Key',
      () async {
        // 先有一个服务商，带一个模型
        await controller.upsertProvider(
          _providerConfig(
            id: 'existing',
            name: 'My API',
            apiUrl: 'https://same.url/api',
            apiKey: 'same-key',
            models: [
              _modelConfig(
                id: 'm-1',
                displayName: 'Charlie',
                modelName: 'model-a',
              ),
            ],
          ),
        );

        // 导入同 URL+Key 的服务商，带有额外模型
        // displayName 与 ID 顺序不一致，验证排序按 displayName 而非插入顺序
        await controller.mergeImportedProviders([
          _providerConfig(
            id: 'imported',
            name: 'Different Name',
            apiUrl: 'https://same.url/api',
            apiKey: 'same-key',
            models: [
              _modelConfig(
                id: 'm-2',
                displayName: 'Alpha',
                modelName: 'model-b',
              ),
              _modelConfig(
                id: 'm-3',
                displayName: 'Bravo',
                modelName: 'model-c',
              ),
            ],
          ),
        ]);

        final state = container.read(llmProviderConfigsProvider);
        expect(state.length, 1);
        final mergedProvider = state.first;
        expect(mergedProvider.id, 'existing');
        expect(mergedProvider.name, 'My API');
        expect(mergedProvider.models.length, 3);
        final modelIds = mergedProvider.models.map((m) => m.id).toSet();
        expect(modelIds, {'m-1', 'm-2', 'm-3'});
        // 模型按 displayName 排序：Alpha < Bravo < Charlie
        expect(mergedProvider.models.map((m) => m.displayName).toList(), [
          'Alpha',
          'Bravo',
          'Charlie',
        ]);
      },
    );

    test('mergeImportedProviders() 用归一化 API 根合并同协议服务商', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'existing',
          apiUrl: 'https://same.url',
          apiKey: 'same-key',
          models: [_modelConfig(id: 'm-1', modelName: 'model-a')],
        ),
      );

      await controller.mergeImportedProviders([
        _providerConfig(
          id: 'imported',
          apiUrl: 'https://same.url/v1/chat/completions',
          apiKey: 'same-key',
          models: [_modelConfig(id: 'm-2', modelName: 'model-b')],
        ),
      ]);

      final state = container.read(llmProviderConfigsProvider);
      expect(state, hasLength(1));
      expect(state.single.id, 'existing');
      expect(state.single.models.map((model) => model.modelName).toSet(), {
        'model-a',
        'model-b',
      });
    });

    test('mergeImportedProviders() 不合并相同 URL 与 Key 的不同协议', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'chat',
          apiUrl: 'https://same.url/v1',
          apiKey: 'same-key',
          apiProtocol: LlmApiProtocol.chatCompletions,
        ),
      );

      await controller.mergeImportedProviders([
        _providerConfig(
          id: 'responses',
          apiUrl: 'https://same.url',
          apiKey: 'same-key',
          apiProtocol: LlmApiProtocol.responses,
        ),
      ]);

      final state = container.read(llmProviderConfigsProvider);
      expect(state, hasLength(2));
      expect(state.map((provider) => provider.apiProtocol).toSet(), {
        LlmApiProtocol.chatCompletions,
        LlmApiProtocol.responses,
      });
    });

    test('mergeImportedProviders() skips duplicate models', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'existing',
          name: 'API',
          apiUrl: 'https://api.example.com',
          apiKey: 'key-1',
          models: [_modelConfig(id: 'm-1', modelName: 'model-a')],
        ),
      );

      // 导入含同 modelName 的模型
      await controller.mergeImportedProviders([
        _providerConfig(
          id: 'imported',
          name: 'API',
          apiUrl: 'https://api.example.com',
          apiKey: 'key-1',
          models: [
            _modelConfig(
              id: 'm-duplicate',
              modelName: 'model-a',
            ), // 同 modelName → 跳过
            _modelConfig(id: 'm-2', modelName: 'model-b'),
          ],
        ),
      ]);

      final state = container.read(llmProviderConfigsProvider);
      expect(state.first.models.length, 2); // 只加了 model-b
    });

    test(
      'mergeImportedProviders() matches by ID and updates URL when same ID but different URL',
      () async {
        // 本地已有服务商，URL 为 youzi.today
        await controller.upsertProvider(
          _providerConfig(
            id: 'same-id',
            name: 'My Provider',
            apiUrl: 'https://youzi.today',
            apiKey: 'key-1',
            models: [
              _modelConfig(
                id: 'm-1',
                displayName: 'Model A',
                modelName: 'model-a',
              ),
            ],
          ),
        );

        // 导入同 ID 但 URL 不同的服务商
        await controller.mergeImportedProviders([
          _providerConfig(
            id: 'same-id',
            name: 'My Provider Updated',
            apiUrl: 'https://api.youzi.today',
            apiKey: 'key-1',
            models: [
              _modelConfig(
                id: 'm-2',
                displayName: 'Model B',
                modelName: 'model-b',
              ),
            ],
          ),
        ]);

        final state = container.read(llmProviderConfigsProvider);
        // 不应产生重复
        expect(state.length, 1);
        final provider = state.first;
        // ID 匹配时，服务商字段被覆盖为传入值
        expect(provider.id, 'same-id');
        expect(provider.name, 'My Provider Updated');
        expect(provider.apiUrl, 'https://api.youzi.today');
        // 模型合并：原有 + 新增
        expect(provider.models.length, 2);
        final modelNames = provider.models.map((m) => m.modelName).toSet();
        expect(modelNames, {'model-a', 'model-b'});
      },
    );

    test(
      'mergeImportedProviders() ID match updates URL even without new models',
      () async {
        await controller.upsertProvider(
          _providerConfig(
            id: 'p-1',
            name: 'Old Name',
            apiUrl: 'https://old.url',
            apiKey: 'same-key',
            models: [_modelConfig(id: 'm-1', modelName: 'model-a')],
          ),
        );

        // 导入同 ID 同模型但 URL 不同的服务商
        await controller.mergeImportedProviders([
          _providerConfig(
            id: 'p-1',
            name: 'New Name',
            apiUrl: 'https://new.url',
            apiKey: 'same-key',
            models: [
              _modelConfig(id: 'm-2', modelName: 'model-a'),
            ], // 同 modelName → 跳过，但 URL 应更新
          ),
        ]);

        final state = container.read(llmProviderConfigsProvider);
        expect(state.length, 1);
        final provider = state.first;
        // 字段更新
        expect(provider.name, 'New Name');
        expect(provider.apiUrl, 'https://new.url');
        // 模型不重复
        expect(provider.models.length, 1);
        expect(provider.models.first.modelName, 'model-a');
      },
    );

    test('导入服务商持久化失败时不发布新状态', () async {
      final seed = _providerConfig(
        id: 'seed-provider',
        name: '种子服务商',
        models: [_modelConfig(modelName: 'seed-model')],
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

      expect(failingController.state, [seed]);
      await expectLater(
        failingController.mergeImportedProviders([
          _providerConfig(
            id: 'imported-provider',
            name: '传入服务商',
            models: [_modelConfig(modelName: 'imported-model')],
          ),
        ]),
        throwsA(isA<StateError>()),
      );

      expect(failingController.state, [seed]);
    });

    // ── deleteProviderById() ────────────────────────────────────────────────

    test('deleteProviderById() removes provider', () async {
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'ToDelete'),
      );
      await controller.upsertProvider(_providerConfig(id: 'p-2', name: 'Keep'));

      await controller.deleteProviderById('p-1');

      final state = container.read(llmProviderConfigsProvider);
      expect(state.length, 1);
      expect(state.first.id, 'p-2');
      expect(readPersisted().length, 1);
    });

    test('deleteProviderById() is no-op for non-existent id', () async {
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'Only'));

      await controller.deleteProviderById('non-existent');

      expect(container.read(llmProviderConfigsProvider).length, 1);
    });

    // ── upsertModel() ───────────────────────────────────────────────────────

    test('upsertModel() adds model to existing provider', () async {
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'OpenAI'),
      );

      await controller.upsertModel(
        providerId: 'p-1',
        model: _modelConfig(
          id: 'm-new',
          displayName: 'GPT-4o',
          modelName: 'gpt-4o',
        ),
      );

      final state = container.read(llmProviderConfigsProvider);
      expect(state.first.models.length, 1);
      expect(state.first.models.first.id, 'm-new');
      expect(state.first.models.first.modelName, 'gpt-4o');
      expect(readPersisted().first.models.length, 1);
    });

    test('upsertModel() updates existing model by id', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'p-1',
          name: 'OpenAI',
          models: [
            _modelConfig(id: 'm-1', displayName: 'Old', modelName: 'old-model'),
          ],
        ),
      );

      await controller.upsertModel(
        providerId: 'p-1',
        model: _modelConfig(
          id: 'm-1',
          displayName: 'New',
          modelName: 'new-model',
        ),
      );

      final model = container
          .read(llmProviderConfigsProvider)
          .first
          .models
          .first;
      expect(model.displayName, 'New');
      expect(model.modelName, 'new-model');
      expect(readPersisted().first.models.first.displayName, 'New');
    });

    test('upsertModel() is no-op for unknown provider', () async {
      await controller.upsertModel(
        providerId: 'non-existent',
        model: _modelConfig(id: 'm-1'),
      );

      expect(container.read(llmProviderConfigsProvider), isEmpty);
    });

    // ── deleteModel() ───────────────────────────────────────────────────────

    test('deleteModel() removes model from provider', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'p-1',
          name: 'OpenAI',
          models: [
            _modelConfig(id: 'm-1', displayName: 'GPT-4'),
            _modelConfig(id: 'm-2', displayName: 'GPT-3.5'),
          ],
        ),
      );

      await controller.deleteModel(providerId: 'p-1', modelId: 'm-1');

      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 1);
      expect(models.first.id, 'm-2');
      expect(readPersisted().first.models.length, 1);
    });

    test('deleteModel() is no-op for unknown provider', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'p-1',
          name: 'OpenAI',
          models: [_modelConfig(id: 'm-1')],
        ),
      );

      await controller.deleteModel(providerId: 'non-existent', modelId: 'm-1');

      expect(container.read(llmProviderConfigsProvider).first.models.length, 1);
    });

    // ── upsertModels() ─────────────────────────────────────────────────────

    test('upsertModels() adds multiple models to existing provider', () async {
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'OpenAI'),
      );

      final addedCount = await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(id: 'm-1', displayName: 'GPT-4o', modelName: 'gpt-4o'),
          _modelConfig(
            id: 'm-2',
            displayName: 'GPT-4o-mini',
            modelName: 'gpt-4o-mini',
          ),
        ],
      );

      expect(addedCount, 2);
      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 2);
      expect(models.map((m) => m.id).toSet(), {'m-1', 'm-2'});
      expect(readPersisted().first.models.length, 2);
    });

    test('upsertModels() skips models with duplicate modelName', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'p-1',
          name: 'OpenAI',
          models: [
            _modelConfig(
              id: 'm-existing',
              displayName: 'Old',
              modelName: 'gpt-4o',
            ),
          ],
        ),
      );

      final addedCount = await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(
            id: 'm-new-1',
            displayName: 'GPT-4o New',
            modelName: 'gpt-4o',
          ), // 重复 modelName -> 跳过
          _modelConfig(
            id: 'm-new-2',
            displayName: 'GPT-4o-mini',
            modelName: 'gpt-4o-mini',
          ),
        ],
      );

      expect(addedCount, 1); // 只新增了 1 个
      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 2); // 原 1 个 + 新增 1 个
      expect(models.map((m) => m.modelName).toSet(), {'gpt-4o', 'gpt-4o-mini'});
    });

    test('upsertModels() returns 0 for unknown provider', () async {
      final addedCount = await controller.upsertModels(
        providerId: 'non-existent',
        models: [_modelConfig(id: 'm-1')],
      );

      expect(addedCount, 0);
      expect(container.read(llmProviderConfigsProvider), isEmpty);
    });

    test('upsertModels() returns 0 for empty list', () async {
      await controller.upsertProvider(
        _providerConfig(
          id: 'p-1',
          name: 'OpenAI',
          models: [_modelConfig(id: 'm-1', displayName: 'Existing')],
        ),
      );

      final addedCount = await controller.upsertModels(
        providerId: 'p-1',
        models: [],
      );

      expect(addedCount, 0);
      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 1);
      expect(models.first.id, 'm-1');
    });

    test('upsertModels() deduplicates within input list', () async {
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'OpenAI'),
      );

      final addedCount = await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(id: 'm-1', displayName: 'First', modelName: 'gpt-4o'),
          _modelConfig(
            id: 'm-2',
            displayName: 'Second',
            modelName: 'gpt-4o',
          ), // 同 modelName -> 跳过
        ],
      );

      expect(addedCount, 1);
      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 1);
      expect(models.first.id, 'm-1');
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
