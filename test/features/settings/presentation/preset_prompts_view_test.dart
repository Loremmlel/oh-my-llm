import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/lists/preset_prompts_view.dart';

import '../../../helpers/fixtures.dart';

void main() {
  testWidgets('预设操作等待时防止重复提交且失败后允许重试', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: PresetPromptsView(
            templates: [TestFixtures.presetPrompt(id: 'pending')],
            onCopy: (_) {
              calls++;
              return calls == 1 ? pending.future : Future.value();
            },
            onEdit: (_) {},
            onDelete: (_) async {},
            onSingleSystemChanged: (_, _) async {},
          ),
        ),
      ),
    );
    final copy = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '复制预设',
    );
    await tester.tap(copy);
    await tester.pump();
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    pending.completeError(StateError('模拟写入失败'));
    await tester.pump();
    expect(find.text('操作失败，请重试'), findsOneWidget);
    await tester.tap(copy);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('操作失败，请重试'), findsNothing);
  });
}
