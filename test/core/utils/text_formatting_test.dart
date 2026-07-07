import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/text_formatting.dart';

void main() {
  group('summarizeText', () {
    for (final tc in [
      ('空字符串返回 emptyText', '', 30, 'fallback', 'fallback'),
      ('纯空白返回 emptyText', '   \n\t  ', 30, 'fallback', 'fallback'),
      ('短文本原样返回', 'hello', 30, '', 'hello'),
      ('换行替换为空格', 'line1\nline2', 30, '', 'line1 line2'),
      ('首尾空白被去除', '  hello  ', 30, '', 'hello'),
    ]) {
      test(tc.$1, () {
        expect(
          summarizeText(tc.$2, maxLength: tc.$3, emptyText: tc.$4),
          tc.$5,
        );
      });
    }

    test('恰好等于 maxLength 不截断', () {
      const text = 'abcdefghij';
      expect(summarizeText(text, maxLength: 10), 'abcdefghij');
    });

    test('超过 maxLength 截断并加省略号', () {
      const text = 'abcdefghijklm';
      expect(summarizeText(text, maxLength: 5), 'abcde...');
    });

    test('默认 emptyText 为空字符串', () {
      expect(summarizeText(''), '');
    });

    test('默认 maxLength 为 30', () {
      final long = 'a' * 31;
      final result = summarizeText(long);
      expect(result.length, equals(33)); // 30 + '...'
      expect(result.endsWith('...'), isTrue);
    });

    test('emoji 截断不切断 surrogate pair', () {
      // 35 个 emoji，maxLength=30 应保留前 30 个完整 emoji
      final emoji = '😀' * 35;
      final result = summarizeText(emoji, maxLength: 30);
      expect(result.endsWith('...'), isTrue);
      final prefix = result.substring(0, result.length - 3);
      // 保留 30 个完整 emoji，无孤立代理对
      expect(prefix.characters.length, equals(30));
      expect(prefix, equals('😀' * 30));
    });
  });
}
