import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/preferences/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/custom_headers_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/font_size_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';

const expectedFormatVersion = 9;

const expectedSectionKeys = <String>[
  'modelProviders',
  'presetPrompts',
  'memoryPrompts',
  'templatePrompts',
  'fixedPromptSequences',
  'customHeaders',
  'outputProcessing',
  'fontSizeSettings',
  'autoRetrySettings',
];

const expectedCanonicalSections = <String, Object?>{
  'modelProviders': <Object?>[
    <String, Object?>{
      'id': 'snapshot-provider',
      'name': '快照服务商',
      'apiUrl': 'https://api.example.test/v1',
      'apiKey': 'test-provider-secret',
      'apiProtocol': 'responses',
      'models': <Object?>[
        <String, Object?>{
          'id': 'snapshot-model',
          'displayName': '快照模型',
          'modelName': 'snapshot-model-name',
          'supportsReasoning': true,
        },
      ],
    },
  ],
  'presetPrompts': <Object?>[
    <String, Object?>{
      'id': 'snapshot-preset',
      'name': '快照预设',
      'messages': <Object?>[
        <String, Object?>{
          'id': 'snapshot-message',
          'role': 'system',
          'title': '系统消息',
          'content': '快照系统内容',
          'placement': 'before',
          'enabled': true,
        },
      ],
      'updatedAt': '2026-08-19T00:00:00.000Z',
    },
  ],
  'memoryPrompts': <Object?>[
    <String, Object?>{
      'id': 'snapshot-memory',
      'name': '快照记忆',
      'content': '快照记忆内容',
      'updatedAt': '2026-08-19T00:00:00.000Z',
    },
  ],
  'templatePrompts': <Object?>[
    <String, Object?>{
      'id': 'snapshot-template',
      'title': '快照模板',
      'content': '固定模板正文',
      'variables': <Object?>[],
      'updatedAt': '2026-08-19T00:00:00.000Z',
    },
  ],
  'fixedPromptSequences': <Object?>[
    <String, Object?>{
      'id': 'snapshot-sequence',
      'name': '快照序列',
      'steps': <Object?>[
        <String, Object?>{
          'id': 'snapshot-step',
          'title': '第一步',
          'content': '快照步骤内容',
        },
      ],
      'updatedAt': '2026-08-19T00:00:00.000Z',
    },
  ],
  'customHeaders': <String, Object?>{
    'headers': <Object?>[
      <String, Object?>{'key': 'X-Test-Token', 'value': 'test-header-secret'},
    ],
  },
  'outputProcessing': <String, Object?>{
    'rules': <Object?>[
      <String, Object?>{
        'id': 'snapshot-rule',
        'title': '快照规则',
        'pattern': '秘密模式',
        'replacement': '[已替换]',
        'order': 2,
        'enabled': true,
      },
    ],
  },
  'fontSizeSettings': <String, Object?>{'bodyFontSize': 18.5},
  'autoRetrySettings': <String, Object?>{
    'maxJitterSeconds': 7,
    'maxRetryCount': 3,
    'retryMode': 'fixedInterval',
    'retryOnAbnormalFinishReason': true,
    'retryOnTimeout': true,
    'timeoutSeconds': 45,
  },
};

Future<({ProviderContainer container, SettingsTransferCoordinator coordinator})>
_newContainer() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.inMemory();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return (
    container: container,
    coordinator: container.read(settingsTransferCoordinatorProvider),
  );
}

void main() {
  test('生产 Coordinator 锁定九个有序 section、六个分组和敏感性', () async {
    final (:coordinator, :container) = await _newContainer();
    await _seedFixtures(container);
    final batch = coordinator.exportGroups(
      SettingsTransferGroup.values.toSet(),
    ) as SettingsExportBatch;

    expect(batch.document.sections.keys, expectedSectionKeys);
    expect(
      coordinator.groups.map((descriptor) => descriptor.group).toList(),
      SettingsTransferGroup.values,
    );
    expect(
      coordinator.groups
          .map((descriptor) => descriptor.containsSensitive)
          .toList(),
      [true, false, false, true, false, false],
    );
    expect(batch.containsSensitive, isTrue);
    expect(
      container.read(settingsTransferCoordinatorProvider),
      same(coordinator),
    );
  });

  test('九项 typed fixture 可从全量导出导入到新容器', () async {
    final source = await _newContainer();
    await _seedFixtures(source.container);
    final exported = source.coordinator.exportGroups(
      SettingsTransferGroup.values.toSet(),
    ) as SettingsExportBatch;
    final destination = await _newContainer();

    final ready = destination.coordinator.prepareDocument(
      exported.document,
    ) as SettingsImportReady;
    expect(
      await ready.batch.execute(confirmedSensitive: true),
      isA<SettingsImportSuccess>(),
    );
    final reexported = destination.coordinator.exportGroups(
      SettingsTransferGroup.values.toSet(),
    ) as SettingsExportBatch;

    expect(
      _sanitize(reexported.document.sections),
      _sanitize(exported.document.sections),
    );
  });

  test('生产 v9 canonical sections 与显式 secret-safe snapshot 一致', () async {
    final (:coordinator, :container) = await _newContainer();
    await _seedFixtures(container);
    final batch = coordinator.exportGroups(
      SettingsTransferGroup.values.toSet(),
    ) as SettingsExportBatch;
    final actualSections = batch.document.sections;
    final document = SettingsTransferDocument(sections: actualSections);

    expect(actualSections.keys.toList(), expectedSectionKeys);
    expect(document.toJson()['formatVersion'], expectedFormatVersion);
    expect(
      document.toJson()['identifier'],
      SettingsTransferDocument.identifier,
    );
    expect(document.sections.keys.toList(), expectedSectionKeys);
    expect(_sanitize(actualSections), _sanitize(expectedCanonicalSections));
    expect(
      ((actualSections['modelProviders']! as List).single as Map)['apiKey'],
      'test-provider-secret',
    );
    expect(
      (((actualSections['customHeaders']! as Map)['headers']! as List).single
          as Map)['value'],
      'test-header-secret',
    );
  });

  test('生产文档不包含本地专属设置', () async {
    final (:coordinator, :container) = await _newContainer();
    await _seedFixtures(container);
    final document = (coordinator.exportGroups(
      SettingsTransferGroup.values.toSet(),
    ) as SettingsExportBatch).document;
    const localOnlyKeys = {
      'chatDefaults',
      'settingsTab',
      'mediaRoot',
      'mediaGridDensity',
      'llmModelConfigs',
    };

    for (final key in localOnlyKeys) {
      expect(document.sections, isNot(contains(key)));
    }
  });

  test('服务商专用合并保留本地身份并追加新模型', () async {
    final (:coordinator, :container) = await _newContainer();
    final local = _providerFixture();
    final incoming = LlmProviderConfig(
      id: 'incoming-provider',
      name: '传入服务商',
      apiUrl: 'https://api.example.test',
      apiKey: local.apiKey,
      apiProtocol: local.apiProtocol,
      models: const [
        LlmProviderModelConfig(
          id: 'incoming-model',
          displayName: '新模型',
          modelName: 'new-model',
          supportsReasoning: false,
        ),
      ],
    );
    await container
        .read(llmProviderConfigsProvider.notifier)
        .replaceAllAfterImport([local]);

    final ready = coordinator.prepareDocument(
      SettingsTransferDocument(
        sections: {
          'modelProviders': [incoming.toJson()],
        },
      ),
    ) as SettingsImportReady;
    expect(
      '${ready.batch.summaryItems.single.label} '
      '${ready.batch.summaryItems.single.trailingText}',
      isNot(contains(local.apiKey)),
    );
    await ready.batch.execute(confirmedSensitive: true);

    final merged = container.read(llmProviderConfigsProvider).single;
    expect(merged.id, local.id);
    expect(merged.models.map((model) => model.modelName), [
      'snapshot-model-name',
      'new-model',
    ]);
  });

  test('四类提示词按内容等价规则去重', () async {
    final (:coordinator, :container) = await _newContainer();
    final now = DateTime.utc(2026, 8, 19);
    final preset = _presetFixture();
    final memory = _memoryFixture();
    final template = _templateFixture();
    final sequence = _sequenceFixture();
    await container.read(presetPromptsProvider.notifier).upsert(preset);
    await container.read(memoryPromptsProvider.notifier).upsert(memory);
    await container.read(templatePromptsProvider.notifier).upsert(template);
    await container
        .read(fixedPromptSequencesProvider.notifier)
        .upsert(sequence);

    final result = coordinator.prepareDocument(
      SettingsTransferDocument(
        sections: {
          'presetPrompts': [
            preset
                .copyWith(
                  id: 'incoming-preset',
                  name: '另一个名字',
                  updatedAt: now.add(const Duration(days: 1)),
                  messages: [
                    preset.messages.single.copyWith(
                      id: 'incoming-message',
                      enabled: false,
                    ),
                  ],
                )
                .toJson(),
          ],
          'memoryPrompts': [
            memory
                .copyWith(
                  id: 'incoming-memory',
                  name: '另一个名字',
                  updatedAt: now.add(const Duration(days: 1)),
                )
                .toJson(),
          ],
          'templatePrompts': [
            template
                .copyWith(
                  id: 'incoming-template',
                  title: '另一个标题',
                  updatedAt: now.add(const Duration(days: 1)),
                )
                .toJson(),
          ],
          'fixedPromptSequences': [
            sequence
                .copyWith(
                  id: 'incoming-sequence',
                  name: '另一个名字',
                  updatedAt: now.add(const Duration(days: 1)),
                  steps: [sequence.steps.single.copyWith(id: 'incoming-step')],
                )
                .toJson(),
          ],
        },
      ),
    );

    expect(result, isA<SettingsImportNoChanges>());
  });

  test('模板编译失败、服务商缺少协议和错误 payload 形状均被拒绝', () async {
    final (:coordinator, :container) = await _newContainer();
    final provider = _providerFixture().toJson()..remove('apiProtocol');
    final invalidTemplate = _templateFixture()
        .copyWith(content: '{{#if 人称 == "一"}}\n未闭合内容')
        .toJson();
    final invalidDocuments = [
      SettingsTransferDocument(
        sections: {
          'modelProviders': [provider],
        },
      ),
      SettingsTransferDocument(
        sections: {
          'templatePrompts': [invalidTemplate],
        },
      ),
      SettingsTransferDocument(
        sections: {
          'presetPrompts': [1],
        },
      ),
      SettingsTransferDocument(sections: const {'customHeaders': []}),
    ];

    for (final document in invalidDocuments) {
      expect(
        coordinator.prepareDocument(document),
        isA<SettingsImportInvalidSectionPayload>(),
      );
    }
  });

  test('Header 与输出规则的空对象保留清空语义且摘要不泄露内容', () async {
    final (:coordinator, :container) = await _newContainer();
    await container
        .read(customHeadersProvider.notifier)
        .save(_headersFixture());
    await container
        .read(outputProcessingSettingsProvider.notifier)
        .save(_outputFixture());

    final ready = coordinator.prepareDocument(
      SettingsTransferDocument(
        sections: {
          'customHeaders': {'headers': <Object?>[]},
          'outputProcessing': {'rules': <Object?>[]},
        },
      ),
    ) as SettingsImportReady;

    expect(ready.batch.summaryItems.map((item) => item.action), [
      SettingsTransferSummaryAction.clear,
      SettingsTransferSummaryAction.clear,
    ]);
    expect(ready.batch.summaryItems.map((item) => item.trailingText), [
      '清空',
      '清空',
    ]);
    expect(
      ready.batch.summaryItems.join(),
      isNot(contains('test-header-secret')),
    );
  });
}

Future<void> _seedFixtures(ProviderContainer container) async {
  await container
      .read(llmProviderConfigsProvider.notifier)
      .replaceAllAfterImport([_providerFixture()]);
  await container.read(presetPromptsProvider.notifier).upsert(_presetFixture());
  await container.read(memoryPromptsProvider.notifier).upsert(_memoryFixture());
  await container
      .read(templatePromptsProvider.notifier)
      .upsert(_templateFixture());
  await container
      .read(fixedPromptSequencesProvider.notifier)
      .upsert(_sequenceFixture());
  await container.read(customHeadersProvider.notifier).save(_headersFixture());
  await container
      .read(outputProcessingSettingsProvider.notifier)
      .save(_outputFixture());
  await container
      .read(fontSizeSettingsProvider.notifier)
      .save(_fontSizeFixture());
  await container
      .read(autoRetrySettingsProvider.notifier)
      .save(_retryFixture());
}

Object? _sanitize(Object? value, [List<String> path = const []]) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _sanitize(entry.value, [
          ...path,
          entry.key as String,
        ]),
    };
  }
  if (value is List) {
    return [for (final item in value) _sanitize(item, path)];
  }
  if (path.lastOrNull == 'apiKey' ||
      (path.contains('headers') && path.lastOrNull == 'value')) {
    return '<secret>';
  }
  return value;
}

LlmProviderConfig _providerFixture() {
  return const LlmProviderConfig(
    id: 'snapshot-provider',
    name: '快照服务商',
    apiUrl: 'https://api.example.test/v1',
    apiKey: 'test-provider-secret',
    apiProtocol: LlmApiProtocol.responses,
    models: [
      LlmProviderModelConfig(
        id: 'snapshot-model',
        displayName: '快照模型',
        modelName: 'snapshot-model-name',
        supportsReasoning: true,
      ),
    ],
  );
}

PresetPrompt _presetFixture() {
  return PresetPrompt(
    id: 'snapshot-preset',
    name: '快照预设',
    messages: const [
      PromptMessage(
        id: 'snapshot-message',
        role: PromptMessageRole.system,
        title: '系统消息',
        content: '快照系统内容',
        placement: PromptMessagePlacement.before,
        enabled: true,
      ),
    ],
    updatedAt: DateTime.utc(2026, 8, 19),
  );
}

MemoryPrompt _memoryFixture() => MemoryPrompt(
  id: 'snapshot-memory',
  name: '快照记忆',
  content: '快照记忆内容',
  updatedAt: DateTime.utc(2026, 8, 19),
);

TemplatePrompt _templateFixture() => TemplatePrompt(
  id: 'snapshot-template',
  title: '快照模板',
  content: '固定模板正文',
  variables: const [],
  updatedAt: DateTime.utc(2026, 8, 19),
);

FixedPromptSequence _sequenceFixture() => FixedPromptSequence(
  id: 'snapshot-sequence',
  name: '快照序列',
  steps: const [
    FixedPromptSequenceStep(
      id: 'snapshot-step',
      title: '第一步',
      content: '快照步骤内容',
    ),
  ],
  updatedAt: DateTime.utc(2026, 8, 19),
);

CustomHeadersConfig _headersFixture() => const CustomHeadersConfig(
  headers: [
    CustomHeaderEntry(key: 'X-Test-Token', value: 'test-header-secret'),
  ],
);

OutputProcessingSettings _outputFixture() => const OutputProcessingSettings(
  rules: [
    OutputRegexRule(
      id: 'snapshot-rule',
      title: '快照规则',
      pattern: '秘密模式',
      replacement: '[已替换]',
      order: 2,
      enabled: true,
    ),
  ],
);

FontSizeSettings _fontSizeFixture() =>
    const FontSizeSettings(bodyFontSize: 18.5);

AutoRetrySettings _retryFixture() => const AutoRetrySettings(
  maxJitterSeconds: 7,
  maxRetryCount: 3,
  retryMode: RetryMode.fixedInterval,
  retryOnAbnormalFinishReason: true,
  retryOnTimeout: true,
  timeoutSeconds: 45,
);
