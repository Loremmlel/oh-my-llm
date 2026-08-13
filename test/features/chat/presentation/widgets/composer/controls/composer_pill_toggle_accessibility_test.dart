import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/presentation/widgets/composer/controls/composer_pill_toggle.dart';

/// 当前持有主焦点的语义节点。
SemanticsFinder _focusedNode() =>
    find.semantics.byFlag(SemanticsFlag.isFocused);

Widget _wrap({
  required bool enabled,
  required bool value,
  ValueChanged<bool>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 100),
          ComposerPillToggle(
            enabled: enabled,
            value: value,
            icon: Icons.psychology,
            label: '深度思考',
            onChanged: onChanged,
          ),
          const TextField(), // sentinel
        ],
      ),
    ),
  );
}

void main() {
  group('ComposerPillToggle 语义', () {
    for (final c in [
      (enabled: true, hasCallback: true, value: false, toggled: false),
      (enabled: true, hasCallback: true, value: true, toggled: true),
      (enabled: false, hasCallback: true, value: false, toggled: false),
      (enabled: true, hasCallback: false, value: false, toggled: false),
    ]) {
      testWidgets(
        'enabled=${c.enabled} callback=${c.hasCallback} value=${c.value}',
        (tester) async {
          final isInteractive = c.enabled && c.hasCallback;
          await tester.pumpWidget(
            _wrap(
              enabled: c.enabled,
              value: c.value,
              onChanged: c.hasCallback ? (_) {} : null,
            ),
          );

          final pill = find.semantics.byLabel('深度思考');
          expect(pill, findsOneWidget);
          expect(
            pill,
            isSemantics(
              label: '深度思考',
              hasToggledState: true,
              isToggled: c.toggled,
              hasEnabledState: true,
              isEnabled: isInteractive,
              hasTapAction: isInteractive,
            ),
          );
        },
      );
    }

    testWidgets('semantics tap、Enter、Space 各只调用一次 onChanged(!value)', (
      tester,
    ) async {
      final calls = <bool>[];
      await tester.pumpWidget(
        _wrap(enabled: true, value: false, onChanged: calls.add),
      );

      tester.semantics.tap(find.semantics.byLabel('深度思考'));
      await tester.pump();
      expect(calls, [true]);

      // Enter 触发前先 Tab 聚焦（semantics tap 不移动焦点）
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, [true, true]);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, [true, true, true]);
    });

    testWidgets('父级以新 value 重建后同一节点保持 toggled 与焦点', (tester) async {
      var current = false;
      final calls = <bool>[];
      Future<void> pump() async {
        await tester.pumpWidget(
          _wrap(
            enabled: true,
            value: current,
            onChanged: (v) {
              calls.add(v);
              current = v;
            },
          ),
        );
      }

      await pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedNode(), isSemantics(label: '深度思考'));

      tester.semantics.tap(find.semantics.byLabel('深度思考'));
      await tester.pump();
      expect(calls, [true]);

      await pump(); // 父级按新 value 重建
      await tester.pump();

      expect(
        find.semantics.byLabel('深度思考'),
        isSemantics(hasToggledState: true, isToggled: true, isFocused: true),
      );
    });

    testWidgets('disabled 时 Tab 跳过 pill 直达 sentinel', (tester) async {
      await tester.pumpWidget(
        _wrap(enabled: false, value: false, onChanged: (_) {}),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedNode(), isSemantics(isTextField: true));
    });
  });
}
