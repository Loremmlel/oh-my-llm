import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/model_provider_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/preference_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/application/preferences/settings_tab_preferences.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/chat_defaults.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';

const expectedFormatVersion = 9;

const expectedParticipantKeys = <String>[
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

Future<({ProviderContainer container, SettingsTransferCatalog catalog})>
_readProductionCatalog() async {
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
    catalog: container.read(settingsTransferCatalogProvider),
  );
}

void main() {
  test('生产 catalog 锁定九个有序 participant、六个分组和敏感性', () async {
    final (:catalog, :container) = await _readProductionCatalog();

    final participants = catalog.participantsForGroups(
      SettingsTransferGroup.values.toSet(),
    );
    expect(
      participants.map((participant) => participant.key.value).toList(),
      expectedParticipantKeys,
    );
    expect(
      catalog.groups.map((descriptor) => descriptor.group).toList(),
      SettingsTransferGroup.values,
    );
    expect(
      catalog.groups.map((descriptor) => descriptor.containsSensitive).toList(),
      [true, false, false, true, false, false],
    );
    expect(
      catalog
          .participant<List<LlmProviderConfig>>(
            const SettingsTransferKey('modelProviders'),
          )
          .sensitivity,
      SettingsTransferSensitivity.credentialBearing,
    );
    expect(
      catalog.participant<List<LlmProviderConfig>>(
        const SettingsTransferKey('modelProviders'),
      ),
      isA<ModelProviderTransferParticipant>(),
    );
    expect(
      catalog.participant<List<PresetPrompt>>(
        const SettingsTransferKey('presetPrompts'),
      ),
      isA<PresetPromptTransferParticipant>(),
    );
    expect(
      catalog.participant<List<MemoryPrompt>>(
        const SettingsTransferKey('memoryPrompts'),
      ),
      isA<MemoryPromptTransferParticipant>(),
    );
    expect(
      catalog.participant<List<TemplatePrompt>>(
        const SettingsTransferKey('templatePrompts'),
      ),
      isA<TemplatePromptTransferParticipant>(),
    );
    expect(
      catalog.participant<List<FixedPromptSequence>>(
        const SettingsTransferKey('fixedPromptSequences'),
      ),
      isA<FixedPromptSequenceTransferParticipant>(),
    );
    expect(
      catalog
          .participant<CustomHeadersConfig>(
            const SettingsTransferKey('customHeaders'),
          )
          .sensitivity,
      SettingsTransferSensitivity.credentialBearing,
    );
    expect(
      catalog.participant<CustomHeadersConfig>(
        const SettingsTransferKey('customHeaders'),
      ),
      isA<CustomHeadersTransferParticipant>(),
    );
    expect(
      catalog
          .participant<OutputProcessingSettings>(
            const SettingsTransferKey('outputProcessing'),
          )
          .sensitivity,
      SettingsTransferSensitivity.standard,
    );
    expect(
      catalog.participant<OutputProcessingSettings>(
        const SettingsTransferKey('outputProcessing'),
      ),
      isA<OutputProcessingTransferParticipant>(),
    );
    expect(
      catalog.participant<FontSizeSettings>(
        const SettingsTransferKey('fontSizeSettings'),
      ),
      isA<FontSizeSettingsTransferParticipant>(),
    );
    expect(
      catalog.participant<AutoRetrySettings>(
        const SettingsTransferKey('autoRetrySettings'),
      ),
      isA<AutoRetrySettingsTransferParticipant>(),
    );
    expect(container.read(settingsTransferCatalogProvider), same(catalog));
  });

  test('生产 catalog 的九个 participant 都能编解码完整 typed fixture', () async {
    final (:catalog, :container) = await _readProductionCatalog();

    _expectRoundTrip(catalog, const SettingsTransferKey('modelProviders'), [
      _providerFixture(),
    ]);
    _expectRoundTrip(catalog, const SettingsTransferKey('presetPrompts'), [
      _presetFixture(),
    ]);
    _expectRoundTrip(catalog, const SettingsTransferKey('memoryPrompts'), [
      _memoryFixture(),
    ]);
    _expectRoundTrip(catalog, const SettingsTransferKey('templatePrompts'), [
      _templateFixture(),
    ]);
    _expectRoundTrip(
      catalog,
      const SettingsTransferKey('fixedPromptSequences'),
      [_sequenceFixture()],
    );
    _expectRoundTrip(
      catalog,
      const SettingsTransferKey('customHeaders'),
      _headersFixture(),
    );
    _expectRoundTrip(
      catalog,
      const SettingsTransferKey('outputProcessing'),
      _outputFixture(),
    );
    _expectRoundTrip(
      catalog,
      const SettingsTransferKey('fontSizeSettings'),
      _fontSizeFixture(),
    );
    _expectRoundTrip(
      catalog,
      const SettingsTransferKey('autoRetrySettings'),
      _retryFixture(),
    );
  });

  test('生产 v9 canonical sections 与显式 secret-safe snapshot 一致', () async {
    final (:catalog, :container) = await _readProductionCatalog();
    final actualSections = <String, Object?>{
      'modelProviders': catalog
          .participant<List<LlmProviderConfig>>(
            const SettingsTransferKey('modelProviders'),
          )
          .encode([_providerFixture()]),
      'presetPrompts': catalog
          .participant<List<PresetPrompt>>(
            const SettingsTransferKey('presetPrompts'),
          )
          .encode([_presetFixture()]),
      'memoryPrompts': catalog
          .participant<List<MemoryPrompt>>(
            const SettingsTransferKey('memoryPrompts'),
          )
          .encode([_memoryFixture()]),
      'templatePrompts': catalog
          .participant<List<TemplatePrompt>>(
            const SettingsTransferKey('templatePrompts'),
          )
          .encode([_templateFixture()]),
      'fixedPromptSequences': catalog
          .participant<List<FixedPromptSequence>>(
            const SettingsTransferKey('fixedPromptSequences'),
          )
          .encode([_sequenceFixture()]),
      'customHeaders': catalog
          .participant<CustomHeadersConfig>(
            const SettingsTransferKey('customHeaders'),
          )
          .encode(_headersFixture()),
      'outputProcessing': catalog
          .participant<OutputProcessingSettings>(
            const SettingsTransferKey('outputProcessing'),
          )
          .encode(_outputFixture()),
      'fontSizeSettings': catalog
          .participant<FontSizeSettings>(
            const SettingsTransferKey('fontSizeSettings'),
          )
          .encode(_fontSizeFixture()),
      'autoRetrySettings': catalog
          .participant<AutoRetrySettings>(
            const SettingsTransferKey('autoRetrySettings'),
          )
          .encode(_retryFixture()),
    };
    final document = SettingsTransferDocument(sections: actualSections);

    expect(actualSections.keys.toList(), expectedParticipantKeys);
    expect(document.toJson()['formatVersion'], expectedFormatVersion);
    expect(
      document.toJson()['identifier'],
      SettingsTransferDocument.identifier,
    );
    expect(document.sections.keys.toList(), expectedParticipantKeys);
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

  test('生产 catalog 不注册本地-only storage key 或类型', () async {
    final (:catalog, :container) = await _readProductionCatalog();
    const localOnlyKeys = {
      'chatDefaults',
      'settingsTab',
      'mediaRoot',
      'mediaGridDensity',
      'llmModelConfigs',
    };

    for (final key in localOnlyKeys) {
      expect(
        () => catalog.groupForKey(SettingsTransferKey(key)),
        throwsA(isA<StateError>()),
        reason: '本地-only key=$key 不应进入生产 catalog',
      );
    }
    final localOnlyTypedLookups = <void Function()>[
      () => catalog.participant<ChatDefaults>(
        const SettingsTransferKey('chatDefaults'),
      ),
      () => catalog.participant<SettingsTabPreferences>(
        const SettingsTransferKey('settingsTab'),
      ),
      () => catalog.participant<String>(const SettingsTransferKey('mediaRoot')),
      () => catalog.participant<AppLayoutDensity>(
        const SettingsTransferKey('mediaGridDensity'),
      ),
      () => catalog.participant<LlmModelConfig>(
        const SettingsTransferKey('llmModelConfigs'),
      ),
    ];
    for (final lookup in localOnlyTypedLookups) {
      expect(lookup, throwsA(isA<StateError>()));
    }
  });

  test('test-only fake participant 可注册到独立 catalog 且不改变生产 snapshot', () async {
    final (:catalog, :container) = await _readProductionCatalog();
    final testOnlyParticipant = _TestOnlyStringParticipant();
    final separateCatalog = SettingsTransferCatalog([
      SettingsTransferParticipantBox.erase(testOnlyParticipant),
    ]);

    expect(
      separateCatalog.participant<String>(testOnlyParticipant.key),
      same(testOnlyParticipant),
    );
    expect(
      catalog
          .participantsForGroups(SettingsTransferGroup.values.toSet())
          .map((participant) => participant.key.value)
          .toList(),
      expectedParticipantKeys,
    );
  });
}

void _expectRoundTrip<T>(
  SettingsTransferCatalog catalog,
  SettingsTransferKey key,
  T value,
) {
  final participant = catalog.participant<T>(key);
  final encoded = participant.encode(value);
  final decoded = participant.decode(jsonDecode(jsonEncode(encoded)));
  final reencoded = participant.encode(decoded);

  expect(_sanitize(reencoded), _sanitize(encoded), reason: key.value);
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

final class _TestOnlyStringParticipant
    extends ReplacingValueParticipant<String> {
  _TestOnlyStringParticipant()
    : super(
        key: const SettingsTransferKey('testOnlyFake9'),
        group: SettingsTransferGroup.other,
        label: '测试专用设置',
        order: 99,
        sensitivity: SettingsTransferSensitivity.standard,
      );

  @override
  String readLocal() => 'local';

  @override
  bool isEquivalent(String existing, String incoming) => existing == incoming;

  @override
  Object encode(String value) => {'value': value};

  @override
  String decode(Object? payload) => (payload as Map)['value'] as String;

  @override
  Future<void> applyImport(String value) async {}
}
