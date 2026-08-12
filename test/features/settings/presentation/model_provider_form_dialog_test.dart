import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/form/model_provider_form_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<void> Function(ModelProviderFormData) onSubmit,
    LlmProviderConfig? initialValue,
  }) async {
    final sp = await SharedPreferences.getInstance();

    await pumpTestApp(
      tester,
      preferences: sp,
      child: Scaffold(
        body: Center(
          child: ModelProviderFormDialog(
            onSubmit: onSubmit,
            initialValue: initialValue,
          ),
        ),
      ),
    );
  }

  /// 在对话框内按可见 label 定位表单输入框。
  Finder formField(String label) => find.descendant(
    of: find.byType(ModelProviderFormDialog),
    matching: find.widgetWithText(TextFormField, label),
  );

  Finder protocolDropdown() => find.descendant(
    of: find.byType(ModelProviderFormDialog),
    matching: find.byType(DropdownButtonFormField<LlmApiProtocol>),
  );

  /// 打开协议下拉并选择指定协议（菜单项在 Overlay 中，不受对话框祖先限制）。
  Future<void> selectProtocol(
    WidgetTester tester,
    LlmApiProtocol protocol,
  ) async {
    await tester.tap(protocolDropdown());
    await settleOverlayTransition(tester);
    await tester.tap(find.text(protocol.displayName).last);
    await settleOverlayTransition(tester);
  }

  Future<void> fillRequiredFields(WidgetTester tester) async {
    await tester.enterText(formField('服务商名称'), 'OpenAI 官方');
    await tester.enterText(formField('API URL'), 'https://api.example.com/v1');
    await tester.enterText(formField('API Key'), 'sk-test-12345678');
    await tester.pump();
  }

  group('ModelProviderFormDialog', () {
    testWidgets('新增服务商默认 Chat Completions 并可提交', (tester) async {
      ModelProviderFormData? captured;
      await pumpDialog(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
      );

      // 未传入 initialValue：下拉默认选中 Chat Completions。
      expect(find.text('Chat Completions'), findsOneWidget);

      await fillRequiredFields(tester);
      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      expect(captured, isNotNull);
      expect(captured!.apiProtocol, LlmApiProtocol.chatCompletions);
      expect(captured!.name, 'OpenAI 官方');
      expect(captured!.apiUrl, 'https://api.example.com/v1');
      expect(captured!.apiKey, 'sk-test-12345678');
    });

    testWidgets('编辑服务商显示并提交原协议', (tester) async {
      ModelProviderFormData? captured;
      await pumpDialog(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
        initialValue: const LlmProviderConfig(
          id: 'p-1',
          name: 'Responses 服务',
          apiUrl: 'https://api.example.com/v1',
          apiKey: 'sk-test',
          apiProtocol: LlmApiProtocol.responses,
        ),
      );

      expect(find.text('Responses'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      expect(captured, isNotNull);
      expect(captured!.apiProtocol, LlmApiProtocol.responses);
      expect(captured!.name, 'Responses 服务');
    });

    for (final protocol in [
      LlmApiProtocol.responses,
      LlmApiProtocol.anthropic,
    ]) {
      testWidgets('可选择并提交 ${protocol.displayName}', (tester) async {
        ModelProviderFormData? captured;
        await pumpDialog(
          tester,
          onSubmit: (data) async {
            captured = data;
          },
        );

        await selectProtocol(tester, protocol);
        await fillRequiredFields(tester);
        await tester.tap(find.text('保存'));
        await settleOverlayTransition(tester);

        expect(captured, isNotNull);
        expect(captured!.apiProtocol, protocol);
      });
    }

    testWidgets('保存中 Back 与 barrier 点击不能关闭表单，保存完成后自动关闭', (tester) async {
      // onSubmit 挂在两个 Completer 上：先确认保存已开始，再手动放行完成，
      // 让 busy 窗口在测试内可确定地保持与结束，不依赖真实延时。
      final submitStarted = Completer<void>();
      final submitDone = Completer<void>();
      // 经 showDialog 以真实 Dialog route 挂载，system Back 与 barrier tap
      // 才会走路由 pop 逻辑——直接嵌在 body 中时根路由永远不可弹，测不出契约。
      final sp = await SharedPreferences.getInstance();
      await pumpTestApp(
        tester,
        preferences: sp,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ModelProviderFormDialog(
                  onSubmit: (data) async {
                    submitStarted.complete();
                    await submitDone.future;
                  },
                ),
              ),
              child: const Text('打开表单'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开表单'));
      await settleOverlayTransition(tester);

      await fillRequiredFields(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await submitStarted.future;
      await tester.pump();

      expect(find.text('保存中...'), findsOneWidget);

      // busy 期间 system Back 不能弹出表单（PopScope canPop=false）。
      await tester.binding.handlePopRoute();
      // 等退场动画收敛：若路由真的在退场，动画结束后对话框必然消失，
      // 单帧 pump 只会停在退场中途、树里仍有对话框，无法区分二者。
      await settleOverlayTransition(tester);
      expect(find.byType(ModelProviderFormDialog), findsOneWidget);

      // busy 期间 barrier 点击同样不能关闭。
      await tester.tapAt(Offset.zero);
      await tester.pump();
      expect(find.byType(ModelProviderFormDialog), findsOneWidget);

      // 保存完成后 isSaving 恢复 false，表单自动关闭。
      submitDone.complete();
      await settleOverlayTransition(tester);
      expect(find.byType(ModelProviderFormDialog), findsNothing);
    });
  });
}
