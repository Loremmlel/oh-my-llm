import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/composer_helpers.dart';

void main() {
  group('effortLabel', () {
    test('low → low', () {
      expect(effortLabel(ReasoningEffort.low), 'low');
    });

    test('medium → med', () {
      expect(effortLabel(ReasoningEffort.medium), 'med');
    });

    test('high → high', () {
      expect(effortLabel(ReasoningEffort.high), 'high');
    });

    test('xhigh → xhigh', () {
      expect(effortLabel(ReasoningEffort.xhigh), 'xhigh');
    });
  });

  group('messageFilterLabel', () {
    test('0 条排除只显示 "上下文过滤"', () {
      expect(messageFilterLabel(0), '上下文过滤');
    });

    test('负数也显示基础文本', () {
      expect(messageFilterLabel(-1), '上下文过滤');
    });

    test('正数显示排除计数', () {
      expect(messageFilterLabel(3), '上下文过滤 · 已排除 3 条');
    });
  });
}
