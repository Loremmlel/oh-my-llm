import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/features/settings/application/preferences/trailing_directive_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/trailing_directive_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../../../../helpers/fixtures.dart';
import 'settings_screen_test_helpers.dart';

void registerSettingsScreenTransferTests() {
  testWidgets('当前标签页决定导出分组而不是全量导出', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      models: [_providerModel()],
      presetPrompts: [TestFixtures.presetPrompt(id: 'preset-1')],
      clipboardWrites: clipboardWrites,
    );

    await tester.tap(find.widgetWithText(TextButton, '导出'));
    await tester.pump();

    expect(clipboardWrites, hasLength(1));
    final document = _decodeDocument(clipboardWrites.single);
    expect(document.sections.keys, ['presetPrompts']);
  });

  testWidgets('在服务商页导入预设文档不受当前标签页限制', (tester) async {
    final preset = TestFixtures.presetPrompt(
      id: 'preset-incoming',
      name: '导入预设',
    );
    await setUpSettingsScreen(
      tester,
      initialTabIndex: 0,
      clipboardText: _documentJson({
        'presetPrompts': [preset.toJson()],
      }),
    );

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pumpAndSettle();
    expect(find.text('检测到配置导入数据'), findsOneWidget);
    expect(find.textContaining('标签不匹配'), findsNothing);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('导入')),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(presetPromptsProvider), contains(preset));
  });

  testWidgets('敏感服务商导出先取消保密，再确认仅复制服务商分组', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      models: [_providerModel(apiKey: 'provider-secret')],
      clipboardWrites: clipboardWrites,
    );

    await tester.tap(find.widgetWithText(TextButton, '导出'));
    await tester.pumpAndSettle();

    expect(find.textContaining('系统剪贴板'), findsOneWidget);
    expect(find.textContaining('provider-secret'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(clipboardWrites, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认复制'));
    await tester.pumpAndSettle();
    expect(clipboardWrites, hasLength(1));
    expect(_decodeDocument(clipboardWrites.single).sections.keys, [
      'modelProviders',
    ]);
    expect(find.textContaining('provider-secret'), findsNothing);
  });

  testWidgets('导入确认摘要和提示不显示 API key 或 Header value', (tester) async {
    const apiKey = 'provider-secret';
    const headerValue = 'header-secret';
    final provider = _provider(apiKey: apiKey);
    await setUpSettingsScreen(
      tester,
      clipboardText: _documentJson({
        'modelProviders': [provider.toJson()],
        'customHeaders': {
          'headers': [
            {'key': 'X-Test', 'value': headerValue},
          ],
        },
      }),
    );

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pumpAndSettle();

    expect(find.text('检测到配置导入数据'), findsOneWidget);
    expect(find.textContaining(apiKey), findsNothing);
    expect(find.textContaining(headerValue), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('导入')),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置已成功导入'), findsOneWidget);
    expect(find.textContaining(apiKey), findsNothing);
    expect(find.textContaining(headerValue), findsNothing);
  });

  testWidgets('其它设置中的末尾指令内容与轮替模式可编辑保存', (tester) async {
    await setUpSettingsScreen(tester);
    await switchToTab(tester, 5);

    final fieldFinder = find.byKey(
      const ValueKey('trailing-directive-content-field'),
    );
    await tester.ensureVisible(fieldFinder);
    await tester.enterText(fieldFinder, '请根据上一条消息作答');
    await tester.pump();

    final switchFinder = find.byKey(
      const ValueKey('trailing-directive-alternating-switch'),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container.read(trailingDirectiveSettingsProvider),
      const TrailingDirectiveSettings(
        content: '请根据上一条消息作答',
        alternatingMode: true,
      ),
    );
  });

  testWidgets('异步持久化未完成时连续输入末尾指令与切换轮替模式不会互相覆盖或重置光标', (tester) async {
    final store = _DelayedTrailingStore();
    await setUpSettingsScreen(
      tester,
      extraOverrides: [settingsKeyValueStoreProvider.overrideWithValue(store)],
    );
    await switchToTab(tester, 5);

    final fieldFinder = find.byKey(
      const ValueKey('trailing-directive-content-field'),
    );
    await tester.ensureVisible(fieldFinder);
    await tester.enterText(fieldFinder, 'a');
    await tester.pump();
    await tester.enterText(fieldFinder, 'ab');
    await tester.pump();

    // 放行第一次未完成的写入后，输入框仍应保持最新文本 'ab' 且光标留在末尾。
    store.completeNext();
    await tester.pump();

    final textField = tester.widget<TextField>(
      find.descendant(of: fieldFinder, matching: find.byType(TextField)),
    );
    expect(textField.controller?.text, 'ab');

    final switchFinder = find.byKey(
      const ValueKey('trailing-directive-alternating-switch'),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();

    while (store.pendingCount > 0) {
      store.completeAll();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container.read(trailingDirectiveSettingsProvider),
      const TrailingDirectiveSettings(content: 'ab', alternatingMode: true),
    );

    // 外部 save 变更内容时仍可正常同步到输入框。
    final externalSave = container
        .read(trailingDirectiveSettingsProvider.notifier)
        .save(
          const TrailingDirectiveSettings(
            content: '外部导入指令',
            alternatingMode: false,
          ),
        );
    store.completeAll();
    await externalSave;
    await tester.pump();
    expect(textField.controller?.text, '外部导入指令');
  });
}

final class _DelayedTrailingStore implements SettingsKeyValueStore {
  final Map<String, Object> _values = {};
  final List<({String key, String value, Completer<bool> completer})> _queue =
      [];

  int get pendingCount => _queue.length;

  void completeNext() {
    if (_queue.isEmpty) return;
    final item = _queue.removeAt(0);
    _values[item.key] = item.value;
    item.completer.complete(true);
  }

  void completeAll() {
    while (_queue.isNotEmpty) {
      completeNext();
    }
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) {
    if (key != trailingDirectiveSettingsStorageKey) {
      _values[key] = value;
      return Future.value(true);
    }
    final completer = Completer<bool>();
    _queue.add((key: key, value: value, completer: completer));
    return completer.future;
  }
}

LlmModelConfig _providerModel({String apiKey = 'sk-test'}) =>
    TestFixtures.model(
      id: 'model-1',
      displayName: '测试模型',
      modelName: 'test-model',
      apiKey: apiKey,
      providerId: 'provider-1',
      providerName: '测试服务商',
    );

LlmProviderConfig _provider({String apiKey = 'sk-test'}) => LlmProviderConfig(
  id: 'provider-1',
  name: '测试服务商',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: apiKey,
  apiProtocol: LlmApiProtocol.chatCompletions,
  models: const [],
);

String _documentJson(Map<String, Object?> sections) =>
    SettingsTransferDocumentCodec.encodeJson(
      SettingsTransferDocument(sections: sections),
    );

SettingsTransferDocument _decodeDocument(String text) {
  final decoded = SettingsTransferDocumentCodec.decodeJson(text);
  expect(decoded, isA<SettingsTransferDocumentDecodeSuccess>());
  return (decoded as SettingsTransferDocumentDecodeSuccess).document;
}
