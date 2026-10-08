import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_field_group.dart';

import '../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('窄容器大字号选择后无需父级重建即可更新提示并保留校验', (tester) async {
    final formKey = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: Form(
                key: formKey,
                child: StatefulBuilder(
                  builder: (context, _) => AppFieldGroup(
                    children: [
                      AppDropdownField<String>(
                        initialValue: selected,
                        decoration: const InputDecoration(labelText: '服务商'),
                        items: const [
                          DropdownMenuItem(
                            value: 'first',
                            child: Text('演示服务商'),
                          ),
                          DropdownMenuItem(
                            value: 'second',
                            child: Text('第二服务商'),
                          ),
                        ],
                        validator: (value) => value == null ? '请选择服务商' : null,
                        onChanged: (value) => selected = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请选择服务商'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('第二服务商').last);
    await settleOverlayTransition(tester);
    expect(selected, 'second');
    expect(find.byTooltip('第二服务商').hitTestable(), findsOneWidget);
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('父级切换选中值后更新显示并保留完整值提示', (tester) async {
    var selected = 'first';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AppDropdownField<String>(
                initialValue: selected,
                items: const [
                  DropdownMenuItem(value: 'first', child: Text('第一个')),
                  DropdownMenuItem(value: 'second', child: Text('第二个完整的长名称')),
                ],
                onChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );
    update(() => selected = 'second');
    await tester.pump();
    expect(find.text('第二个完整的长名称').hitTestable(), findsOneWidget);
    expect(find.byTooltip('第二个完整的长名称').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选项列表移除内部选中项后恢复空值与表单校验', (tester) async {
    final formKey = GlobalKey<FormState>();
    var includeSecond = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AppDropdownField<String>(
                  decoration: const InputDecoration(hintText: '选择项目'),
                  items: [
                    const DropdownMenuItem(value: 'first', child: Text('第一个')),
                    if (includeSecond)
                      const DropdownMenuItem(
                        value: 'second',
                        child: Text('第二个'),
                      ),
                  ],
                  onChanged: (_) {},
                  validator: (value) => value == null ? '请选择项目' : null,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('第二个').last);
    await settleOverlayTransition(tester);
    expect(formKey.currentState!.validate(), isTrue);
    update(() => includeSecond = false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请选择项目'), findsOneWidget);
  });
}
