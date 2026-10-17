import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/providers/model_capability_chips.dart';

void main() {
  testWidgets('点击能力文字和键盘空格分别切换一次，语义不重复', (tester) async {
    var reasoning = false;
    var image = false;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ModelCapabilityChips(
              supportsReasoning: reasoning,
              supportsImageInput: image,
              onReasoningChanged: (value) => setState(() {
                reasoning = value;
                changes++;
              }),
              onImageInputChanged: (value) => setState(() {
                image = value;
                changes++;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('深度思考'));
    await tester.pump();
    expect(reasoning, isTrue);
    expect(changes, 1);
    await tester.tap(find.text('图像'));
    await tester.pump();
    expect(image, isTrue);
    expect(changes, 2);
    expect(find.semantics.byLabel('图像'), findsOneWidget);
    expect(find.semantics.byLabel('深度思考'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(reasoning, isFalse);
    expect(changes, 3);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(reasoning, isTrue);
    expect(changes, 4);
  });

  testWidgets('能力禁用时点击文字和复选框都保持原值', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ModelCapabilityChips(
            supportsReasoning: false,
            supportsImageInput: true,
            onReasoningChanged: null,
            onImageInputChanged: null,
          ),
        ),
      ),
    );
    await tester.tap(find.text('深度思考'));
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(
      find.semantics.byLabel('深度思考'),
      isSemantics(
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    expect(
      find.semantics.byLabel('图像'),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
  });
}
