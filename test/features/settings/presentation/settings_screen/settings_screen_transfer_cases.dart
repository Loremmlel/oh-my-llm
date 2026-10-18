import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
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
