import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/fields/number_variable_field.dart';

void main() {
  testWidgets('数字步进器按阅读顺序先减少再增加并保留整数编辑', (tester) async {
    final controller = TextEditingController(text: '800');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Center(
            child: NumberVariableField(
              controller: controller,
              labelText: '目标字数',
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '799');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '800');
    expect(controller.selection.baseOffset, controller.text.length);
    await tester.enterText(find.byType(TextField), '-1');
    await tester.tap(find.byTooltip('减少目标字数'));
    await tester.pump();
    expect(controller.text, '-2');
  });
}
