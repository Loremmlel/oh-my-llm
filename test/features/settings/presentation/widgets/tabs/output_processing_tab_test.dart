import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/application/preferences/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/tabs/output_processing_tab.dart';

import '../../../../../helpers/test_harness.dart';
import '../../../../../helpers/async/widget_test_animation.dart';

OutputRegexRule _rule({
  String id = 'rule-1',
  String title = '过滤增殖',
  String pattern = '极其',
  String replacement = '',
  int order = 0,
  bool enabled = true,
}) {
  return OutputRegexRule(
    id: id,
    title: title,
    pattern: pattern,
    replacement: replacement,
    order: order,
    enabled: enabled,
  );
}

void main() {
  group('输出正则处理', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    Future<ProviderContainer> pumpTab(
      WidgetTester tester, {
      List<OutputRegexRule> initialRules = const [],
    }) async {
      await pumpTestApp(
        tester,
        preferences: preferences,
        child: const Scaffold(body: OutputProcessingTab()),
        extraOverrides: initialRules.isEmpty
            ? const []
            : [
                outputProcessingSettingsProvider.overrideWith(
                  () => _FakeController(initialRules),
                ),
              ],
      );
      return ProviderScope.containerOf(tester.element(find.text('输出正则处理')));
    }

    // ── 渲染 ──────────────────────────────────────────────────

    // ── 新增 ──────────────────────────────────────────────────

    testWidgets('新增对话框拒绝无效正则', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settleOverlayTransition(tester);

      await tester.enterText(
        find.widgetWithText(TextField, '正则表达式'),
        '[invalid',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.textContaining('无效正则'), findsOneWidget);
    });

    testWidgets('新增对话框提交合法值后规则出现在列表', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settleOverlayTransition(tester);

      await tester.enterText(find.widgetWithText(TextField, '标题'), '新规则');
      await tester.enterText(find.widgetWithText(TextField, '正则表达式'), r'\d+');
      await tester.tap(find.text('保存'));
      // 表单提交后对话框出场，列表随保存状态更新
      await settleOverlayTransition(tester);

      expect(find.text('新规则'), findsOneWidget);
    });

    // ── 编辑 ──────────────────────────────────────────────────

    // ── 开关 ──────────────────────────────────────────────────

    // ── 移动 ──────────────────────────────────────────────────

    testWidgets('切换启用状态后下移保留新状态与顺序', (tester) async {
      final rules = [
        _rule(id: 'a', title: '规则A', order: 0),
        _rule(id: 'b', title: '规则B', order: 1),
      ];
      final container = await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      final downButtons = find.byIcon(Icons.arrow_downward_rounded);
      await tester.tap(downButtons.first);
      await tester.pump();

      final result = container.read(outputProcessingSettingsProvider).rules;
      expect(result.map((rule) => rule.title), ['规则B', '规则A']);
      expect(result.last.enabled, isFalse);
    });

    // ── 删除 ──────────────────────────────────────────────────

    testWidgets('确认删除后规则移除', (tester) async {
      final rules = [_rule(title: '待删除')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await settleOverlayTransition(tester);
      expect(find.text('确认删除'), findsOneWidget);

      await tester.tap(find.text('删除'));
      // 确认对话框出场，同时删除状态已保存
      await settleOverlayTransition(tester);

      expect(find.text('待删除'), findsNothing);
    });
  });
}

class _FakeController extends Notifier<OutputProcessingSettings>
    implements OutputProcessingSettingsController {
  final List<OutputRegexRule> _initialRules;

  _FakeController(this._initialRules);

  @override
  OutputProcessingSettings build() {
    return OutputProcessingSettings(rules: _initialRules);
  }

  @override
  Future<void> save(OutputProcessingSettings settings) async {
    state = settings;
  }
}
