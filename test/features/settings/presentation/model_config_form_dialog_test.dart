import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/model_list_client.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/form/model_config_form_dialog.dart';

import '../../../helpers/test_harness.dart';

void main() {
  LlmProviderConfig testProvider = const LlmProviderConfig(
    id: 'p-1',
    name: 'TestProvider',
    apiUrl: 'https://api.example.com/v1/chat/completions',
    apiKey: 'sk-test',
    models: [],
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    testProvider = const LlmProviderConfig(
      id: 'p-1',
      name: 'TestProvider',
      apiUrl: 'https://api.example.com/v1/chat/completions',
      apiKey: 'sk-test',
      models: [],
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<void> Function(ModelConfigFormData) onSubmit,
    required Future<void> Function(List<ModelBatchFormData>) onBatchAdd,
    required Future<List<RemoteModelInfo>> Function({
      required String modelsUrl,
      required String apiKey,
    }) fetchModels,
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

  group('ModelConfigFormDialog', () {
    group('manual mode', () {
      testWidgets('shows manual form by default for new model', (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async => [],
        );

        expect(find.text('显示名称'), findsOneWidget);
        expect(find.text('API 模型名称'), findsOneWidget);
        expect(find.text('支持深度思考'), findsOneWidget);
      });

      testWidgets('hides mode switch when editing existing model',
          (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async => [],
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
          fetchModels: ({required modelsUrl, required apiKey}) async => [],
        );

        await tester.enterText(
          find.byKey(const ValueKey('model-config-display-name-field')),
          'My Model',
        );
        await tester.enterText(
          find.byKey(const ValueKey('model-config-api-name-field')),
          'my-model',
        );
        await tester.pump();

        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.displayName, 'My Model');
        expect(captured!.modelName, 'my-model');
        expect(captured!.supportsReasoning, false);
      });
    });

    group('fetch mode', () {
      testWidgets('shows fetch section when switching to fetch mode',
          (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async => [],
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        expect(find.byKey(const ValueKey('model-fetch-button')), findsOneWidget);
      });

      testWidgets('shows loading state when fetching', (tester) async {
        final completer = Completer<List<RemoteModelInfo>>();
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) => completer.future,
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.text('正在拉取...'), findsOneWidget);

        completer.complete([]);
        await tester.pumpAndSettle();
      });

      testWidgets('shows error message on fetch failure', (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            throw const ModelListException('服务器返回错误（401）', statusCode: 401);
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('服务器返回错误'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      });

      testWidgets('shows model list after successful fetch', (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [
              const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai'),
              const RemoteModelInfo(id: 'gpt-4o-mini', ownedBy: 'openai'),
            ];
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        expect(find.text('gpt-4o'), findsWidgets);
        expect(find.text('gpt-4o-mini'), findsWidgets);
      });

      testWidgets('shows already-exists chip for existing models',
          (tester) async {
        testProvider = const LlmProviderConfig(
          id: 'p-1',
          name: 'TestProvider',
          apiUrl: 'https://api.example.com/v1/chat/completions',
          apiKey: 'sk-test',
          models: [
            LlmProviderModelConfig(
              id: 'm-existing',
              displayName: 'GPT-4o',
              modelName: 'gpt-4o',
              supportsReasoning: false,
            ),
          ],
        );

        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai')];
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        expect(find.text('已存在'), findsOneWidget);
      });

      testWidgets('disables submit button until models are selected',
          (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai')];
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        final submitButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('添加所选模型'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(submitButton.onPressed, isNull);
      });

      testWidgets('enables submit when at least one model is selected',
          (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai')];
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('model-fetch-checkbox-gpt-4o')),
        );
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
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (items) async {
            captured = items;
          },
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [
              const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai'),
              const RemoteModelInfo(id: 'gpt-4o-mini', ownedBy: 'openai'),
            ];
          },
        );

        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('model-fetch-checkbox-gpt-4o')),
        );
        await tester.pump();

        await tester.tap(find.text('添加所选模型'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.length, 1);
        expect(captured!.first.modelName, 'gpt-4o');
        expect(captured!.first.displayName, 'gpt-4o');
      });

      testWidgets('preserves fetch state when switching modes',
          (tester) async {
        await pumpDialog(
          tester,
          onSubmit: (_) async {},
          onBatchAdd: (_) async {},
          fetchModels: ({required modelsUrl, required apiKey}) async {
            return [const RemoteModelInfo(id: 'gpt-4o', ownedBy: 'openai')];
          },
        );

        // 切到拉取模式
        await tester.tap(find.text('从 API 拉取'));
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('model-fetch-button')));
        await tester.pumpAndSettle();

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
