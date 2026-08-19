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
import '../../../../helpers/async/widget_test_animation.dart';
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

    await tester.tap(find.byIcon(Icons.upload_rounded));
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
    await settleOverlayTransition(tester);
    expect(find.text('检测到配置导入数据'), findsOneWidget);
    expect(find.textContaining('标签不匹配'), findsNothing);

    await tester.tap(find.text('导入'));
    await settleOverlayTransition(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(presetPromptsProvider), contains(preset));
  });

  testWidgets('敏感服务商导出取消时不写入系统剪贴板', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      models: [_providerModel(apiKey: 'provider-secret')],
      clipboardWrites: clipboardWrites,
    );

    await tester.tap(find.byIcon(Icons.upload_rounded));
    await settleOverlayTransition(tester);

    expect(find.textContaining('系统剪贴板'), findsOneWidget);
    expect(find.textContaining('provider-secret'), findsNothing);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);

    expect(clipboardWrites, isEmpty);
  });

  testWidgets('确认敏感服务商导出只写入 modelProviders section', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      models: [_providerModel(apiKey: 'provider-secret')],
      clipboardWrites: clipboardWrites,
    );

    await tester.tap(find.byIcon(Icons.upload_rounded));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('确认复制'));
    await settleOverlayTransition(tester);

    expect(clipboardWrites, hasLength(1));
    final document = _decodeDocument(clipboardWrites.single);
    expect(document.sections.keys, ['modelProviders']);
    expect(find.textContaining('provider-secret'), findsNothing);
    expect(find.textContaining('provider-header-secret'), findsNothing);
  });

  testWidgets('空自定义请求头导出保留显式空 replacement section', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(tester, clipboardWrites: clipboardWrites);
    await switchToTab(tester, 3);

    await tester.tap(find.byIcon(Icons.upload_rounded));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('确认复制'));
    await settleOverlayTransition(tester);

    final document = _decodeDocument(clipboardWrites.single);
    expect(document.sections.keys, ['customHeaders']);
    expect(document.sections['customHeaders'], {'headers': <Object?>[]});
  });

  testWidgets('空输出处理导出保留显式空 replacement section', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(tester, clipboardWrites: clipboardWrites);
    await switchToTab(tester, 4);

    await tester.tap(find.byIcon(Icons.upload_rounded));
    await tester.pump();

    final document = _decodeDocument(clipboardWrites.single);
    expect(document.sections.keys, ['outputProcessing']);
    expect(document.sections['outputProcessing'], {'rules': <Object?>[]});
  });

  testWidgets('剪贴板 malformed 文档显示无效消息', (tester) async {
    await setUpSettingsScreen(tester, clipboardText: '{not-json');

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pump();

    expect(find.text('导入内容无效'), findsOneWidget);
    expect(find.text('不支持的设置传输版本'), findsNothing);
    expect(find.text('没有可导入的变化'), findsNothing);
  });

  testWidgets('剪贴板 v8 文档显示版本不支持消息', (tester) async {
    await setUpSettingsScreen(
      tester,
      clipboardText:
          '{"identifier":"shikiyuzu-oh-my-llm","formatVersion":8,"sections":{}}',
    );

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pump();

    expect(find.text('不支持的设置传输版本'), findsOneWidget);
    expect(find.text('导入内容无效'), findsNothing);
    expect(find.text('没有可导入的变化'), findsNothing);
  });

  testWidgets('剪贴板未知 section 显示未知设置项消息', (tester) async {
    await setUpSettingsScreen(
      tester,
      clipboardText: _documentJson({'unknownSection': <String, Object?>{}}),
    );

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pump();

    expect(find.text('未知设置项：unknownSection'), findsOneWidget);
    expect(find.text('导入内容无效'), findsNothing);
    expect(find.text('没有可导入的变化'), findsNothing);
  });

  testWidgets('剪贴板无变化文档显示无可导入变化消息', (tester) async {
    await setUpSettingsScreen(
      tester,
      clipboardText: _documentJson(const <String, Object?>{}),
    );

    await tester.tap(find.byTooltip('从剪贴板导入设置'));
    await tester.pump();

    expect(find.text('没有可导入的变化'), findsOneWidget);
    expect(find.text('导入内容无效'), findsNothing);
    expect(find.text('不支持的设置传输版本'), findsNothing);
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
    await settleOverlayTransition(tester);

    expect(find.text('检测到配置导入数据'), findsOneWidget);
    expect(find.textContaining(apiKey), findsNothing);
    expect(find.textContaining(headerValue), findsNothing);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
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
