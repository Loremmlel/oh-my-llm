import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

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
  List<LlmProviderModelConfig>? models,
}) {
  return LlmProviderConfig(
    id: id,
    name: name,
    apiUrl: apiUrl,
    apiKey: apiKey,
    models: models ?? [],
  );
}

void main() {
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

    test('build() returns stored providers from SharedPreferences', () async {
      final provider = _providerConfig(
        id: 'p-1',
        name: 'DeepSeek',
        apiUrl: 'https://api.deepseek.com/v1/chat/completions',
        apiKey: 'sk-deepseek',
        models: [_modelConfig(id: 'm-1', displayName: 'DeepSeek-V3', modelName: 'deepseek-chat')],
      );
      await controller.upsertProvider(provider);

      final persisted = readPersisted();
      expect(persisted.length, 1);
      expect(persisted.first.id, 'p-1');
      expect(persisted.first.name, 'DeepSeek');
      expect(persisted.first.models.length, 1);
      expect(persisted.first.models.first.id, 'm-1');
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
      await controller.upsertProvider(_providerConfig(id: 'p-3', name: 'Charlie'));
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'Alpha'));
      await controller.upsertProvider(_providerConfig(id: 'p-2', name: 'Bravo'));

      final names =
          container.read(llmProviderConfigsProvider).map((p) => p.name).toList();
      expect(names, ['Alpha', 'Bravo', 'Charlie']);
    });

    // ── upsertAllProviders() ────────────────────────────────────────────────

    test('upsertAllProviders() adds multiple new providers', () async {
      await controller.upsertAllProviders([
        _providerConfig(id: 'p-2', name: 'Beta'),
        _providerConfig(id: 'p-1', name: 'Alpha'),
      ]);

      final names =
          container.read(llmProviderConfigsProvider).map((p) => p.name).toList();
      expect(names, ['Alpha', 'Beta']);
      expect(readPersisted().length, 2);
    });

    test('upsertAllProviders() updates existing and adds new in one call', () async {
      // 先添加一个已存在的
      await controller.upsertProvider(
        _providerConfig(id: 'p-1', name: 'Old Name', apiUrl: 'https://old.url'),
      );

      // 批量调用：更新 p-1 + 新增 p-2
      await controller.upsertAllProviders([
        _providerConfig(id: 'p-1', name: 'New Name', apiUrl: 'https://new.url'),
        _providerConfig(id: 'p-2', name: 'Brand New'),
      ]);

      final state = container.read(llmProviderConfigsProvider);
      expect(state.length, 2);
      expect(state.firstWhere((p) => p.id == 'p-1').name, 'New Name');
      expect(state.firstWhere((p) => p.id == 'p-2').name, 'Brand New');
      expect(readPersisted().length, 2);
    });

    // ── mergeImportedProviders() ────────────────────────────────────────────

    test('mergeImportedProviders() adds new provider', () async {
      await controller.mergeImportedProviders([
        _providerConfig(id: 'p-1', name: 'Imported'),
      ]);

      expect(container.read(llmProviderConfigsProvider).length, 1);
    });

    test('mergeImportedProviders() merges models for same API URL+Key', () async {
      // 先有一个服务商，带一个模型
      await controller.upsertProvider(_providerConfig(
        id: 'existing',
        name: 'My API',
        apiUrl: 'https://same.url/api',
        apiKey: 'same-key',
        models: [_modelConfig(id: 'm-1', displayName: 'Charlie', modelName: 'model-a')],
      ));

      // 导入同 URL+Key 的服务商，带有额外模型
      // displayName 与 ID 顺序不一致，验证排序按 displayName 而非插入顺序
      await controller.mergeImportedProviders([
        _providerConfig(
          id: 'imported',
          name: 'Different Name',
          apiUrl: 'https://same.url/api',
          apiKey: 'same-key',
          models: [
            _modelConfig(id: 'm-2', displayName: 'Alpha', modelName: 'model-b'),
            _modelConfig(id: 'm-3', displayName: 'Bravo', modelName: 'model-c'),
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
    });

    test('mergeImportedProviders() skips duplicate models', () async {
      await controller.upsertProvider(_providerConfig(
        id: 'existing',
        name: 'API',
        apiUrl: 'https://api.example.com',
        apiKey: 'key-1',
        models: [_modelConfig(id: 'm-1', modelName: 'model-a')],
      ));

      // 导入含同 modelName 的模型
      await controller.mergeImportedProviders([
        _providerConfig(
          id: 'imported',
          name: 'API',
          apiUrl: 'https://api.example.com',
          apiKey: 'key-1',
          models: [
            _modelConfig(id: 'm-duplicate', modelName: 'model-a'), // 同 modelName → 跳过
            _modelConfig(id: 'm-2', modelName: 'model-b'),
          ],
        ),
      ]);

      final state = container.read(llmProviderConfigsProvider);
      expect(state.first.models.length, 2); // 只加了 model-b
    });

    // ── deleteProviderById() ────────────────────────────────────────────────

    test('deleteProviderById() removes provider', () async {
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'ToDelete'));
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
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'OpenAI'));

      await controller.upsertModel(
        providerId: 'p-1',
        model: _modelConfig(id: 'm-new', displayName: 'GPT-4o', modelName: 'gpt-4o'),
      );

      final state = container.read(llmProviderConfigsProvider);
      expect(state.first.models.length, 1);
      expect(state.first.models.first.id, 'm-new');
      expect(state.first.models.first.modelName, 'gpt-4o');
      expect(readPersisted().first.models.length, 1);
    });

    test('upsertModel() updates existing model by id', () async {
      await controller.upsertProvider(_providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        models: [_modelConfig(id: 'm-1', displayName: 'Old', modelName: 'old-model')],
      ));

      await controller.upsertModel(
        providerId: 'p-1',
        model: _modelConfig(id: 'm-1', displayName: 'New', modelName: 'new-model'),
      );

      final model = container.read(llmProviderConfigsProvider).first.models.first;
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
      await controller.upsertProvider(_providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        models: [
          _modelConfig(id: 'm-1', displayName: 'GPT-4'),
          _modelConfig(id: 'm-2', displayName: 'GPT-3.5'),
        ],
      ));

      await controller.deleteModel(providerId: 'p-1', modelId: 'm-1');

      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 1);
      expect(models.first.id, 'm-2');
      expect(readPersisted().first.models.length, 1);
    });

    test('deleteModel() is no-op for unknown provider', () async {
      await controller.upsertProvider(_providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        models: [_modelConfig(id: 'm-1')],
      ));

      await controller.deleteModel(providerId: 'non-existent', modelId: 'm-1');

      expect(container.read(llmProviderConfigsProvider).first.models.length, 1);
    });

    // ── upsertModels() ─────────────────────────────────────────────────────

    test('upsertModels() adds multiple models to existing provider', () async {
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'OpenAI'));

      await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(id: 'm-1', displayName: 'GPT-4o', modelName: 'gpt-4o'),
          _modelConfig(id: 'm-2', displayName: 'GPT-4o-mini', modelName: 'gpt-4o-mini'),
        ],
      );

      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 2);
      expect(models.map((m) => m.id).toSet(), {'m-1', 'm-2'});
      expect(readPersisted().first.models.length, 2);
    });

    test('upsertModels() skips models with duplicate modelName', () async {
      await controller.upsertProvider(_providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        models: [_modelConfig(id: 'm-existing', displayName: 'Old', modelName: 'gpt-4o')],
      ));

      await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(id: 'm-new-1', displayName: 'GPT-4o New', modelName: 'gpt-4o'), // 重复 modelName -> 跳过
          _modelConfig(id: 'm-new-2', displayName: 'GPT-4o-mini', modelName: 'gpt-4o-mini'),
        ],
      );

      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 2); // 原 1 个 + 新增 1 个
      expect(models.map((m) => m.modelName).toSet(), {'gpt-4o', 'gpt-4o-mini'});
    });

    test('upsertModels() is no-op for unknown provider', () async {
      await controller.upsertModels(
        providerId: 'non-existent',
        models: [_modelConfig(id: 'm-1')],
      );

      expect(container.read(llmProviderConfigsProvider), isEmpty);
    });

    test('upsertModels() with empty list does not modify state', () async {
      await controller.upsertProvider(_providerConfig(
        id: 'p-1',
        name: 'OpenAI',
        models: [_modelConfig(id: 'm-1', displayName: 'Existing')],
      ));

      await controller.upsertModels(providerId: 'p-1', models: []);

      final models = container.read(llmProviderConfigsProvider).first.models;
      expect(models.length, 1);
      expect(models.first.id, 'm-1');
    });

    test('upsertModels() persists changes', () async {
      await controller.upsertProvider(_providerConfig(id: 'p-1', name: 'OpenAI'));

      await controller.upsertModels(
        providerId: 'p-1',
        models: [
          _modelConfig(id: 'm-1', displayName: 'GPT-4o', modelName: 'gpt-4o'),
        ],
      );

      final persisted = readPersisted();
      expect(persisted.first.models.length, 1);
      expect(persisted.first.models.first.id, 'm-1');
    });

  });
}
