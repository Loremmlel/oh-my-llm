import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/application/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/tab/output_processing_tab.dart';

import '../../../helpers/test_harness.dart';

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
  group('OutputProcessingTab', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    Future<void> pumpTab(
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
                outputProcessingSettingsProvider
                    .overrideWith(() => _FakeController(initialRules)),
              ],
      );
    }

    // ── 渲染 ──────────────────────────────────────────────────

    testWidgets('空规则时显示占位文本', (tester) async {
      await pumpTab(tester);
      expect(find.text('暂无正则规则，点击上方按钮添加'), findsOneWidget);
    });

    testWidgets('已有规则时显示规则卡片', (tester) async {
      final rules = [
        _rule(id: 'a', title: '规则A', pattern: r'\d+', order: 0),
        _rule(id: 'b', title: '规则B', pattern: 'foo', order: 1),
      ];
      await pumpTab(tester, initialRules: rules);
      expect(find.text('规则A'), findsOneWidget);
      expect(find.text('规则B'), findsOneWidget);
    });

    // ── 新增 ──────────────────────────────────────────────────

    testWidgets('点击新增按钮打开 dialog', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('新增正则规则'), findsOneWidget);
    });

    testWidgets('dialog 中空表达式校验失败', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('表达式不能为空'), findsOneWidget);
    });

    testWidgets('dialog 中无效正则校验失败', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '正则表达式'),
        '[invalid',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.textContaining('无效正则'), findsOneWidget);
    });

    testWidgets('dialog 填写合法值提交后规则出现在列表', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '标题'),
        '新规则',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '正则表达式'),
        r'\d+',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('新规则'), findsOneWidget);
    });

    // ── 编辑 ──────────────────────────────────────────────────

    testWidgets('点击编辑按钮打开预填 dialog', (tester) async {
      final rules = [_rule(title: '编辑测试', pattern: 'abc')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('编辑正则规则'), findsOneWidget);
    });

    testWidgets('编辑提交后规则更新', (tester) async {
      final rules = [_rule(title: '旧标题', pattern: 'abc')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextField, '标题');
      await tester.enterText(titleField, '新标题');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('新标题'), findsOneWidget);
    });

    // ── 开关 ──────────────────────────────────────────────────

    testWidgets('点击 Switch 切换启用/禁用', (tester) async {
      final rules = [_rule(enabled: true)];
      await pumpTab(tester, initialRules: rules);

      final switchWidget = find.byType(Switch);
      expect(switchWidget, findsOneWidget);

      await tester.tap(switchWidget);
      await tester.pumpAndSettle();
    });

    // ── 移动 ──────────────────────────────────────────────────

    testWidgets('下移按钮改变规则顺序', (tester) async {
      final rules = [
        _rule(id: 'a', title: '规则A', order: 0),
        _rule(id: 'b', title: '规则B', order: 1),
      ];
      await pumpTab(tester, initialRules: rules);

      final downButtons = find.byIcon(Icons.arrow_downward_rounded);
      await tester.tap(downButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('规则A'), findsOneWidget);
      expect(find.text('规则B'), findsOneWidget);
    });

    // ── 删除 ──────────────────────────────────────────────────

    testWidgets('点击删除弹出确认 dialog', (tester) async {
      final rules = [_rule(title: '待删除')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('确认删除'), findsOneWidget);
    });

    testWidgets('确认删除后规则移除', (tester) async {
      final rules = [_rule(title: '待删除')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('待删除'), findsNothing);
    });

    testWidgets('取消删除后规则保留', (tester) async {
      final rules = [_rule(title: '保留规则')];
      await pumpTab(tester, initialRules: rules);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('保留规则'), findsOneWidget);
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
