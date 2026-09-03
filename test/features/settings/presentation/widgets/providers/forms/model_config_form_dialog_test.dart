import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/providers/model_catalog_workflow.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/model_catalog_entry.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart';

import '../../../../../../helpers/test_harness.dart';
import '../../../../../../helpers/async/widget_test_animation.dart';

void main() {
  LlmProviderConfig testProvider = const LlmProviderConfig(
    id: 'p-1',
    name: 'TestProvider',
    apiUrl: 'https://api.example.com/v1/chat/completions',
    apiKey: 'sk-test',
    apiProtocol: LlmApiProtocol.chatCompletions,
    models: [],
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    testProvider = const LlmProviderConfig(
      id: 'p-1',
      name: 'TestProvider',
      apiUrl: 'https://api.example.com/v1/chat/completions',
      apiKey: 'sk-test',
      apiProtocol: LlmApiProtocol.chatCompletions,
      models: [],
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<void> Function(ModelConfigFormData) onSubmit,
    required Future<void> Function(List<ModelBatchFormData>) onBatchAdd,
    required Future<List<ModelCatalogEntry>> Function(
      ModelCatalogRequest request,
    )
    fetchModels,
  }) async {
    final sp = await SharedPreferences.getInstance();

    await pumpTestApp(
      tester,
      preferences: sp,
      child: Scaffold(
        body: Center(
          child: ModelConfigFormDialog(
            provider: testProvider,
            onSubmit: onSubmit,
            onBatchAdd: onBatchAdd,
            fetchModels: fetchModels,
          ),
        ),
      ),
    );
  }

  /// 在模型对话框内按可见 label 定位表单输入框。
  Finder modelField(String label) => find.descendant(
    of: find.byType(ModelConfigFormDialog),
    matching: find.widgetWithText(TextFormField, label),
  );

  /// 按远端模型名定位所属行的选择框；模型名唯一标识该行。
  Finder modelCheckbox(String remoteModelId) {
    final row = find.widgetWithText(Row, remoteModelId);
    return find.descendant(of: row, matching: find.byType(Checkbox));
  }

  /// 切换到拉取模式并点击拉取按钮，随后断言按钮进入加载态。
  Future<void> switchToFetchAndClickFetch(WidgetTester tester) async {
    await tester.tap(find.text('从 API 拉取'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '拉取模型'));
    await tester.pump();
    expect(find.text('正在拉取...'), findsOneWidget);
  }

  group('模型表单', () {
    group('手动输入', () {
      testWidgets('保存时提交手动输入的模型', (tester) async {
        ModelConfigFormData? captured;
        await pumpDialog(
          tester,
          onSubmit: (data) async {
            captured = data;
          },
          onBatchAdd: (_) async {},
          fetchModels: (_) async => [],
        );

        await tester.enterText(modelField('显示名称'), 'My Model');
        await tester.enterText(modelField('API 模型名称'), 'my-model');
        await tester.pump();

        await tester.tap(find.text('保存'));
        // 提交后对话框出场，提交 Future 随帧完成
        await settleOverlayTransition(tester);

        expect(captured, isNotNull);
        expect(captured!.displayName, 'My Model');
        expect(captured!.modelName, 'my-model');
        expect(captured!.supportsReasoning, false);
      });
    });

    group('从 API 拉取', () {
      testWidgets('拉取请求携带服务商的非默认协议', (tester) async {
        testProvider = const LlmProviderConfig(
          id: 'p-1',
          name: 'TestProvider',
          apiUrl: 'https://api.anthropic.com',
          apiKey: 'sk-ant-test',
          apiProtocol: LlmApiProtocol.anthropic,
          models: [],
        );
        LlmApiProtocol? capturedProtocol;
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (request) async {
            capturedProtocol = request.apiProtocol;
            return completer.future;
          },
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete(const []);
        await tester.pump();

        expect(capturedProtocol, LlmApiProtocol.anthropic);
      });

      testWidgets('拉取失败后显示错误并可重试成功', (tester) async {
        final firstRequest = Completer<List<ModelCatalogEntry>>();
        final retryRequest = Completer<List<ModelCatalogEntry>>();
        var requestCount = 0;
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) =>
              requestCount++ == 0 ? firstRequest.future : retryRequest.future,
        );

        await switchToFetchAndClickFetch(tester);

        firstRequest.completeError(const ModelCatalogFailure('服务器返回错误（401）'));
        await tester.pump();

        expect(find.textContaining('服务器返回错误'), findsOneWidget);
        await tester.tap(find.text('重试'));
        await tester.pump();
        retryRequest.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        expect(requestCount, 2);
        expect(find.text('gpt-4o'), findsWidgets);
      });

      testWidgets('仅提交勾选的远程模型', (tester) async {
        List<ModelBatchFormData>? captured;
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (items) async {
            captured = items;
          },
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        await tester.tap(find.text('添加所选模型'), warnIfMissed: false);
        await tester.pump();
        expect(captured, isNull);

        await tester.tap(modelCheckbox('gpt-4o'));
        await tester.pump();

        await tester.tap(find.text('添加所选模型'));
        // 批量添加后对话框出场，onBatchAdd Future 随帧完成
        await settleOverlayTransition(tester);

        expect(captured, isNotNull);
        expect(captured!.length, 1);
        expect(captured!.first.modelName, 'gpt-4o');
        expect(captured!.first.displayName, 'gpt-4o');
      });
    });
  });
}
