import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('候选编辑器保留长文并支持跨行替换与撤销重做', () {
    final original = '${'中文🙂e\u0301👩‍💻\n' * 5000}结尾';
    final controller = CodeLineEditingController.fromText(original);
    addTearDown(controller.dispose);
    expect(controller.text, original);
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 2,
      extentOffset: 0,
    );
    controller.replaceSelection('替换\n');
    final edited = controller.text;
    expect(edited, '替换\n${original.split('\n').skip(2).join('\n')}');
    controller.undo();
    expect(controller.text, original);
    controller.redo();
    expect(controller.text, edited);
  });

  test('候选编辑器退格不拆开组合字符和表情', () {
    for (final grapheme in ['🙂', 'e\u0301', '👩‍💻']) {
      final controller = CodeLineEditingController.fromText('甲$grapheme乙');
      controller.selection = CodeLineSelection.collapsed(
        index: 0,
        offset: 1 + grapheme.length,
      );
      controller.deleteBackward();
      expect(controller.text, '甲乙', reason: grapheme);
      controller.dispose();
    }
  });

  test('候选编辑器默认配置原样保留混合换行符', () {
    const original = '甲\r\n乙\n丙\r\n';
    final controller = CodeLineEditingController.fromText(original);
    addTearDown(controller.dispose);
    expect(controller.text, original);
  });

  testWidgets('候选编辑器处理当前行的拼音组合与中文提交增量', (tester) async {
    final controller = CodeLineEditingController.fromText('前文\n后文');
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            focusNode: focus,
            autocompleteSymbols: false,
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
          ),
        ),
      ),
    );
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );
    focus.requestFocus();
    await tester.pump();
    final client =
        tester.testTextInput.log
                .lastWhere((call) => call.method == 'TextInput.setClient')
                .arguments[0]
            as int;

    Future<void> delta(
      String old,
      String replacement,
      int start,
      int end,
      int caret,
      int composingStart,
      int composingEnd,
    ) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', [
            client,
            {
              'deltas': [
                {
                  'oldText': old,
                  'deltaText': replacement,
                  'deltaStart': start,
                  'deltaEnd': end,
                  'selectionBase': caret,
                  'selectionExtent': caret,
                  'selectionAffinity': 'TextAffinity.downstream',
                  'selectionIsDirectional': false,
                  'composingBase': composingStart,
                  'composingExtent': composingEnd,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await delta('后文', 'ni', 2, 2, 4, 2, 4);
    expect(controller.text, '前文\n后文ni');
    expect(controller.composing, const TextRange(start: 2, end: 4));
    await delta('后文ni', '你', 2, 4, 3, -1, -1);
    expect(controller.text, '前文\n后文你');
    expect(controller.composing, TextRange.empty);
    // 候选组件在输入后延迟 50ms 更新补全状态；先完成该有限回调再卸载。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final candidate in [false, true]) {
    testWidgets('${candidate ? '候选' : '原生'}编辑器向辅助技术暴露可编辑正文', (tester) async {
      final handle = tester.ensureSemantics();
      final text = TextEditingController(text: '可访问的正文');
      final code = CodeLineEditingController.fromText(text.text);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: candidate
                ? CodeEditor(
                    controller: code,
                    chunkAnalyzer: const NonCodeChunkAnalyzer(),
                  )
                : TextField(controller: text, maxLines: null),
          ),
        ),
      );
      final nodes = <SemanticsNode>[];
      void collect(SemanticsNode node) {
        nodes.add(node);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      final exposesText = nodes.any((node) {
        final data = node.getSemanticsData();
        return data.flagsCollection.isTextField && data.value == text.text;
      });
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
      text.dispose();
      code.dispose();
      expect(exposesText, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
