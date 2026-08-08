import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/presentation/widgets/media_path_bar.dart';

import '../../../helpers/responsive_viewport_cases.dart';

/// 当前持有主焦点的语义节点。
SemanticsFinder _focusedNode() =>
    find.semantics.byFlag(SemanticsFlag.isFocused);

Widget _wrap(MediaPathBar bar) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 100),
          bar,
          const TextField(), // sentinel：验证 disabled/结尾后焦点去向
        ],
      ),
    ),
  );
}

void main() {
  group('MediaPathBar 语义', () {
    testWidgets('currentPath=/相册/旅行 时语义顺序为根目录→相册→旅行，末项 selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(MediaPathBar(currentPath: '/相册/旅行', onPathSelected: (_) {})),
      );

      expect(find.semantics.byLabel('根目录'), findsOneWidget);
      expect(find.semantics.byLabel('目录：相册'), findsOneWidget);
      final last = find.semantics.byLabel('目录：旅行');
      expect(last, findsOneWidget);
      expect(
        last,
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      expect(find.semantics.byLabel('根目录'), isSemantics(isSelected: false));
    });

    testWidgets('根目录时只有根目录 chip 且 selected', (tester) async {
      await tester.pumpWidget(
        _wrap(MediaPathBar(currentPath: '/', onPathSelected: (_) {})),
      );

      expect(find.semantics.byLabel('根目录'), findsOneWidget);
      expect(find.semantics.byLabel('目录：'), findsNothing);
      expect(find.semantics.byLabel('根目录'), isSemantics(isSelected: true));
    });

    testWidgets('semantics tap 根目录与中间 segment 分别回调 / 与 /相册', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        _wrap(
          MediaPathBar(currentPath: '/相册/旅行', onPathSelected: selected.add),
        ),
      );

      tester.semantics.tap(find.semantics.byLabel('目录：相册'));
      await tester.pump();
      expect(selected, ['/相册']);

      tester.semantics.tap(find.semantics.byLabel('根目录'));
      await tester.pump();
      expect(selected, ['/相册', '/']);
    });

    testWidgets('Tab+Enter 按根到叶顺序触发相同 path', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        _wrap(
          MediaPathBar(currentPath: '/相册/旅行', onPathSelected: selected.add),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedNode(), isSemantics(label: '根目录'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['/']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['/', '/相册']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, ['/', '/相册', '/相册/旅行']);
    });
  });

  group('MediaPathBar 视口', () {
    for (final vp in [phonePortrait, wideDesktop]) {
      testWidgets('${vp.name} 下长路径可 Tab 到末级并激活', (tester) async {
        final selected = <String>[];
        tester.view.physicalSize = vp.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const longPath = '/相册/旅行/家庭/2025/春天/樱花';
        await tester.pumpWidget(
          _wrap(
            MediaPathBar(currentPath: longPath, onPathSelected: selected.add),
          ),
        );

        // 1 根 + 6 级 segment
        for (var i = 0; i < 7; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(_focusedNode(), isSemantics(label: '目录：樱花'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(selected, [longPath]);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
