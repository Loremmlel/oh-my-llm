import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

void main() {
  test('加载混合换行用于显示且未编辑保存保留原始字符串', () {
    const original = '甲\r\n\r\n乙\r丙\n🙂';
    final controller = LongTextEditingController(text: original);
    addTearDown(controller.dispose);
    expect(controller.text, '甲\n\n乙\n丙\n🙂');
    expect(controller.textForSave(), original);
    expect(controller.hasTextChanges, isFalse);
    controller.selection = const TextSelection.collapsed(offset: 1);
    expect(controller.textForSave(), original);
  });

  test('粘贴含代理对和混合换行时保留反向选区及光标亲和性', () {
    final controller = LongTextEditingController();
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: '🙂甲\r\n乙\r丙\r\n丁',
      selection: TextSelection(
        baseOffset: 11,
        extentOffset: 5,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    expect(controller.text, '🙂甲\n乙\n丙\n丁');
    expect(controller.selection.baseOffset, 9);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.affinity, TextAffinity.upstream);
    expect(controller.selection.isDirectional, isTrue);
  });

  test('无选区的程序赋值及单独回车不会生成越界偏移', () {
    final controller = LongTextEditingController();
    addTearDown(controller.dispose);
    controller.text = '甲\r\n乙\r丙';
    expect(controller.text, '甲\n乙\n丙');
    expect(controller.selection.baseOffset, -1);
    controller.value = const TextEditingValue(
      text: '甲\r乙',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange.collapsed(3),
    );
    expect(controller.text, '甲\n乙');
    expect(controller.selection.extentOffset, 3);
    expect(controller.value.composing, const TextRange.collapsed(3));
  });

  test('组字中不改写平台文本和组合区提交后再归一化', () {
    final controller = LongTextEditingController();
    addTearDown(controller.dispose);
    const composing = TextEditingValue(
      text: '甲\r\nni',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 3, end: 5),
    );
    controller.value = composing;
    expect(controller.value, composing);
    controller.value = const TextEditingValue(
      text: '甲\r\n你',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(controller.text, '甲\n你');
    expect(controller.selection.extentOffset, 3);
    expect(controller.value.composing, TextRange.empty);
  });

  test('改动后保存LF而恢复原文后恢复原始换行', () {
    final controller = LongTextEditingController(text: '甲\r\n乙');
    addTearDown(controller.dispose);
    controller.text = '甲\r\n乙丙';
    expect(controller.hasTextChanges, isTrue);
    expect(controller.textForSave(), '甲\n乙丙');
    controller.text = '甲\n乙';
    expect(controller.hasTextChanges, isFalse);
    expect(controller.textForSave(), '甲\r\n乙');
    controller.loadText('另一个\r草稿');
    expect(controller.text, '另一个\n草稿');
    expect(controller.textForSave(), '另一个\r草稿');
  });

  test('保存去空白策略只作用于改动后的文本且不改变转义字面量', () {
    final controller = LongTextEditingController(text: ' 甲\r\n乙 ');
    addTearDown(controller.dispose);
    expect(controller.textForSave(trim: true), ' 甲\r\n乙 ');
    controller.text = ' 新\r\n文\\r\\n ';
    expect(controller.textForSave(trim: true), '新\n文\\r\\n');
  });

  testWidgets('平台粘贴更新后的显示回调和光标均使用LF', (tester) async {
    final controller = LongTextEditingController(text: '甲\r\n乙');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            maxLines: null,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲\n乙\r\n🙂',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();
    expect(controller.text, '甲\n乙\n🙂');
    expect(controller.selection.extentOffset, 6);
    expect(changes.last, controller.text);
    expect(tester.takeException(), isNull);
  });

  testWidgets('平台输入连接的中文组字和提交保持组合区有效', (tester) async {
    final controller = LongTextEditingController(text: '甲\r\n');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    const composing = TextEditingValue(
      text: '甲\nni',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(controller.value, composing);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲\n你',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(controller.textForSave(), '甲\n你');
    expect(controller.value.composing, TextRange.empty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('粘贴撤销重做保持LF显示并在撤销后保留原文', (tester) async {
    // Flutter UndoHistory 使用 500ms 节流窗口，推进到快照提交边界。
    const undoHistoryThrottle = Duration(milliseconds: 500);
    final controller = LongTextEditingController(text: '甲\r\n乙');
    final undo = UndoHistoryController();
    addTearDown(controller.dispose);
    addTearDown(undo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            undoController: undo,
            maxLines: null,
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump(undoHistoryThrottle);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲\n乙\r\n丙',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump(undoHistoryThrottle);
    expect(controller.text, '甲\n乙\n丙');
    expect(undo.value.canUndo, isTrue);
    undo.undo();
    await tester.pump();
    expect(controller.text, '甲\n乙');
    expect(controller.textForSave(), '甲\r\n乙');
    undo.redo();
    await tester.pump();
    expect(controller.text, '甲\n乙\n丙');
    expect(controller.textForSave(), '甲\n乙\n丙');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
