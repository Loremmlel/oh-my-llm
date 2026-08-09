import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

void main() {
  group('useCompactShell', () {
    test('仅在 719 走紧凑分支，720 等号属宽侧', () {
      expect(AppBreakpoints.useCompactShell(719), isTrue);
      expect(AppBreakpoints.useCompactShell(720), isFalse);
    });
  });

  group('useCompactFormActions', () {
    test('仅在 679 走紧凑分支，680 等号属宽侧', () {
      expect(AppBreakpoints.useCompactFormActions(679), isTrue);
      expect(AppBreakpoints.useCompactFormActions(680), isFalse);
    });
  });

  group('useFullWidthMessageBubble', () {
    test('仅在 599 走近全宽分支，600 等号属宽侧', () {
      expect(AppBreakpoints.useFullWidthMessageBubble(599), isTrue);
      expect(AppBreakpoints.useFullWidthMessageBubble(600), isFalse);
    });
  });
}
