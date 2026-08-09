import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/model_catalog_workflow.dart';
import 'package:oh_my_llm/features/settings/domain/models/model_catalog_entry.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/form/model_config_form_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';

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
    LlmProviderModelConfig? initialValue,
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
            initialValue: initialValue,
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

  group('ModelConfigFormDialog', () {
    group('manual mode', () {
      testWidgets('shows manual form by default for new model', (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) async => [],
        );

        expect(find.text('显示名称'), findsOneWidget);
        expect(find.text('API 模型名称'), findsOneWidget);
        expect(find.text('支持深度思考'), findsOneWidget);
      });

      testWidgets('hides mode switch when editing existing model', (
        tester,
      ) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) async => [],
          initialValue: const LlmProviderModelConfig(
            id: 'm-1',
            displayName: 'Existing',
            modelName: 'existing-model',
            supportsReasoning: false,
          ),
        );

        expect(find.text('手动输入'), findsNothing);
        expect(find.text('从 API 拉取'), findsNothing);
        expect(find.text('编辑模型'), findsOneWidget);
      });

      testWidgets('submits form data on save', (tester) async {
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

    group('fetch mode', () {
      testWidgets('shows fetch section when switching to fetch mode', (
        tester,
      ) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) async => [],
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        expect(find.widgetWithText(FilledButton, '拉取模型'), findsOneWidget);
      });

      testWidgets('passes the provider apiProtocol in the catalog request', (
        tester,
      ) async {
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

      testWidgets('shows loading state when fetching', (tester) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('正在拉取模型列表...'), findsOneWidget);

        completer.complete([]);
        await tester.pump();
      });

      testWidgets('shows error message on fetch failure', (tester) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.completeError(const ModelCatalogFailure('服务器返回错误（401）'));
        await tester.pump();

        expect(find.textContaining('服务器返回错误'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      });

      testWidgets('shows model list after successful fetch', (tester) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
          const ModelCatalogEntry(id: 'gpt-4o-mini', ownedBy: 'openai'),
        ]);
        await tester.pump();

        expect(find.text('gpt-4o'), findsWidgets);
        expect(find.text('gpt-4o-mini'), findsWidgets);
      });

      testWidgets('shows already-exists chip for existing models', (
        tester,
      ) async {
        testProvider = const LlmProviderConfig(
          id: 'p-1',
          name: 'TestProvider',
          apiUrl: 'https://api.example.com/v1/chat/completions',
          apiKey: 'sk-test',
          apiProtocol: LlmApiProtocol.chatCompletions,
          models: [
            LlmProviderModelConfig(
              id: 'm-existing',
              displayName: 'GPT-4o',
              modelName: 'gpt-4o',
              supportsReasoning: false,
            ),
          ],
        );
        final completer = Completer<List<ModelCatalogEntry>>();

        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        expect(find.text('已存在'), findsOneWidget);
      });

      testWidgets('disables submit button until models are selected', (
        tester,
      ) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        final submitButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('添加所选模型'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(submitButton.onPressed, isNull);
      });

      testWidgets('enables submit when at least one model is selected', (
        tester,
      ) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        await tester.tap(modelCheckbox('gpt-4o'));
        await tester.pump();

        final submitButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('添加所选模型'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(submitButton.onPressed, isNotNull);
      });

      testWidgets('calls onBatchAdd with selected models', (tester) async {
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
          const ModelCatalogEntry(id: 'gpt-4o-mini', ownedBy: 'openai'),
        ]);
        await tester.pump();

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

      testWidgets('preserves fetch state when switching modes', (tester) async {
        final completer = Completer<List<ModelCatalogEntry>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: (_) => completer.future,
        );

        await switchToFetchAndClickFetch(tester);

        completer.complete([
          const ModelCatalogEntry(id: 'gpt-4o', ownedBy: 'openai'),
        ]);
        await tester.pump();

        // 切回手动
        await tester.tap(find.text('手动输入'));
        await tester.pump();

        // 再切回拉取
        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        // 列表应该还在（state 保存在 widget 中）
        expect(find.text('gpt-4o'), findsWidgets);
      });
    });
  });
}
