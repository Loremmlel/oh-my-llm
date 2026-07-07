import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/chat_word_counter.dart';

void main() {
  // ── countChatWords ────────────────────────────────────────────

  group('countChatWords', () {
    final cases = <(String input, int expected)>[
      ('', 0),
      ('   ', 0),
      ('，。！？', 0),
      ('你好世界', 4),
      ('hello world', 2),
      ('你好 hello 世界', 5),
      ('hello', 1),
      ('a', 1),
      ('你', 1),
      ('你好，hello！世界', 5),
      ('123 456', 0),
      ('你好123世界', 4),
      ('Hello, World! 你好', 4),
      ('région', 2),
      ('café 你好', 3),
      ('😀😀你好', 2), // emoji（代理对）不计字
      ('你好👍世界', 4), // 代理对不影响 CJK 计数
    ];

    for (final (input, expected) in cases) {
      test('"$input" → $expected', () {
        expect(countChatWords(input), expected);
      });
    }
  });

  // ── StreamingChatWordCounter ──────────────────────────────────

  group('StreamingChatWordCounter', () {
    test('增量 update 结果与一次性 update 一致', () {
      const fullText = '你好 hello 世界！这是 test 123。';
      final batch = countChatWords(fullText);

      final streaming = StreamingChatWordCounter();
      for (var i = 1; i <= fullText.length; i++) {
        streaming.update(fullText.substring(0, i));
      }
      expect(streaming.count, batch);
    });

    test('文本变短时 reset 并重新计数', () {
      final counter = StreamingChatWordCounter();
      counter.update('你好 hello');
      expect(counter.count, 3);

      // 文本变短 → 触发 reset，重新计数为 2
      counter.update('你好');
      expect(counter.count, 2);
    });

    test('reset 清零后可重新计数', () {
      final counter = StreamingChatWordCounter();
      counter.update('你好 hello');
      expect(counter.count, 3);

      counter.reset();
      expect(counter.count, 0);

      counter.update('世界 world');
      expect(counter.count, 3);
    });

    test('连续 update 同一文本幂等', () {
      final counter = StreamingChatWordCounter();
      counter.update('你好 hello');
      final first = counter.count;
      counter.update('你好 hello');
      expect(counter.count, first);
    });

    test('空串 update 会触发 reset 清零计数', () {
      final counter = StreamingChatWordCounter();
      counter.update('你好');
      expect(counter.count, 2);

      // 空串长度 0 < _processedLength → reset
      counter.update('');
      expect(counter.count, 0);
    });
  });

  // ── 字符判定函数边界 ─────────────────────────────────────────

  group('isCjkCharacter', () {
    test('CJK 基本汉字范围内为 true', () {
      expect(isCjkCharacter('一'), isTrue);
      expect(isCjkCharacter('龥'), isTrue);
    });

    test('CJK 扩展 A 范围内为 true', () {
      expect(isCjkCharacter(String.fromCharCode(0x3400)), isTrue);
      expect(isCjkCharacter(String.fromCharCode(0x4dbf)), isTrue);
    });

    test('兼容表意文字范围内为 true', () {
      expect(isCjkCharacter(String.fromCharCode(0xf900)), isTrue);
      expect(isCjkCharacter(String.fromCharCode(0xfaff)), isTrue);
    });

    test('ASCII 与中文边界为 false', () {
      expect(isCjkCharacter(String.fromCharCode(0x4dff)), isFalse);
      expect(isCjkCharacter(String.fromCharCode(0x9fff)), isTrue);
      expect(isCjkCharacter(String.fromCharCode(0xa000)), isFalse);
    });

    test('英文字母与数字为 false', () {
      expect(isCjkCharacter('a'), isFalse);
      expect(isCjkCharacter('Z'), isFalse);
      expect(isCjkCharacter('1'), isFalse);
    });

    test('emoji 代理对为 false（按首个 code unit 判定，落在代理区段）', () {
      expect(isCjkCharacter('😀'), isFalse); // U+1F600，UTF-16 代理对
      expect(isCjkCharacter('👍'), isFalse);
    });
  });

  group('isEnglishLetter', () {
    test('大小写字母为 true', () {
      expect(isEnglishLetter('a'), isTrue);
      expect(isEnglishLetter('z'), isTrue);
      expect(isEnglishLetter('A'), isTrue);
      expect(isEnglishLetter('Z'), isTrue);
    });

    test('字母与符号边界为 false', () {
      expect(isEnglishLetter(String.fromCharCode(0x40)), isFalse); // @
      expect(isEnglishLetter(String.fromCharCode(0x5b)), isFalse); // [
      expect(isEnglishLetter(String.fromCharCode(0x60)), isFalse); // `
      expect(isEnglishLetter(String.fromCharCode(0x7b)), isFalse); // {
    });

    test('中文与数字为 false', () {
      expect(isEnglishLetter('你'), isFalse);
      expect(isEnglishLetter('1'), isFalse);
    });
  });
}
