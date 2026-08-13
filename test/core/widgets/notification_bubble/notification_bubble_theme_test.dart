import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_data.dart';

/// 读取气泡的实际配色：背景来自气泡内 Container 的 BoxDecoration，
/// 文字来自唯一的 message Text。颜色本身没有可观察的语义/文本替代品，
/// 这里把「配色方向」当作视觉契约直接断言，而非像素定位。
(Color, Color) _readColors(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(NotificationBubbleContent),
      matching: find.byType(Container),
    ),
  );
  final bg = (container.decoration! as BoxDecoration).color!;
  final text = tester.widget<Text>(find.byType(Text)).style!.color!;
  return (bg, text);
}

void main() {
  group('NotificationBubbleContent 主题配色', () {
    testWidgets('light 主题：浅色背景 + 深色文字，与主应用同向', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: Center(
              child: NotificationBubbleContent(
                data: NotificationBubbleData(message: '同步完成'),
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      final (bg, text) = _readColors(tester);
      expect(
        bg.computeLuminance(),
        greaterThan(0.5),
        reason: 'light 下气泡应为浅色背景',
      );
      expect(text.computeLuminance(), lessThan(0.3), reason: 'light 下气泡文字应为深色');
    });

    testWidgets('dark 主题：深色背景 + 浅色文字，与主应用同向', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Center(
              child: NotificationBubbleContent(
                data: NotificationBubbleData(message: '同步完成'),
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

      final (bg, text) = _readColors(tester);
      expect(bg.computeLuminance(), lessThan(0.5), reason: 'dark 下气泡应为深色背景');
      expect(
        text.computeLuminance(),
        greaterThan(0.5),
        reason: 'dark 下气泡文字应为浅色',
      );
    });
  });
}
