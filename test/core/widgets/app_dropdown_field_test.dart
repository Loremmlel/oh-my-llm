import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_field_group.dart';

void main() {
  testWidgets('统一下拉箭头仍保留字段帮助与选项选择入口', (tester) async {
    var helpOpened = false;
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppDropdownField<String>(
              initialValue: 'first',
              decoration: InputDecoration(
                labelText: '项目',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '项目说明',
                      onPressed: () => helpOpened = true,
                      icon: const Icon(Icons.help_outline),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'first', child: Text('第一个')),
                DropdownMenuItem(value: 'second', child: Text('第二个')),
              ],
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('项目说明'));
    expect(helpOpened, isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二个').last);
    await tester.pumpAndSettle();
    expect(selected, 'second');
    expect(tester.takeException(), isNull);
  });

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
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二服务商').last);
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二个').last);
    await tester.pumpAndSettle();
    expect(formKey.currentState!.validate(), isTrue);
    update(() => includeSecond = false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请选择项目'), findsOneWidget);
  });
}
