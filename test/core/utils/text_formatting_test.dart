import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/text_formatting.dart';

void main() {
  group('summarizeText', () {
    test('空白回退、去除首尾空白并把换行转换为空格', () {
      for (final tc in [
        ('空字符串返回 emptyText', '', 30, 'fallback', 'fallback'),
        ('纯空白返回 emptyText', '   \n\t  ', 30, 'fallback', 'fallback'),
        ('短文本原样返回', 'hello', 30, '', 'hello'),
        ('换行替换为空格', 'line1\nline2', 30, '', 'line1 line2'),
        ('首尾空白被去除', '  hello  ', 30, '', 'hello'),
      ]) {
        expect(
          summarizeText(tc.$2, maxLength: tc.$3, emptyText: tc.$4),
          tc.$5,
          reason: tc.$1,
        );
      }
      expect(summarizeText(''), '');
    });

    test('长度边界不截断，超出自定义或默认长度时添加省略号', () {
      expect(summarizeText('abcdefghij', maxLength: 10), 'abcdefghij');
      expect(summarizeText('abcdefghijklm', maxLength: 5), 'abcde...');
      expect(summarizeText('a' * 31), '${'a' * 30}...');
    });

    test('emoji 截断不切断 surrogate pair', () {
      // 35 个 emoji，maxLength=30 应保留前 30 个完整 emoji
      final emoji = '😀' * 35;
      expect(summarizeText(emoji, maxLength: 30), '${'😀' * 30}...');
    });
  });
}
