import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

import '../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('帮助按键盘打开和关闭后恢复焦点且不修改草稿', (tester) async {
    final controller = TextEditingController(text: '未保存的内容');
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const AppHelpTitle(title: '模板', message: '模板的完整解释'),
              TextField(controller: controller),
            ],
          ),
        ),
      ),
    );
    expect(find.text('模板的完整解释'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final help = find.byType(IconButton);
    expect(
      tester.getSemantics(help).flagsCollection.isFocused,
      Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleOverlayTransition(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('模板的完整解释'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlayTransition(tester);
    expect(find.text('模板的完整解释'), findsNothing);
    expect(controller.text, '未保存的内容');
    expect(
      tester.getSemantics(help).flagsCollection.isFocused,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('窄屏大字号长帮助独立滚动且关闭按钮可达', (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final message = List.filled(30, '这是一段需要阅读和复制的详细说明。').join('\n\n');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsSectionCard(
            title: '较长的设置分组名称',
            description: message,
            child: const Text('主要操作区域'),
          ),
        ),
      ),
    );
    expect(find.text(message), findsNothing);
    await tester.tap(find.byTooltip('较长的设置分组名称说明'));
    await settleOverlayTransition(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await settleScrollMotion(tester);
    await tester.tap(find.text('关闭'));
    await settleOverlayTransition(tester);
    expect(find.text('主要操作区域').hitTestable(), findsOneWidget);
    expect(find.text(message), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
