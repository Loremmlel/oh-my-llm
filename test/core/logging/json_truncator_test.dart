import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/json_truncator.dart';

/// 截断后缀字符串和其长度
const _suffix = '...[truncated]';
const _suffixLen = 14;
const _maxLen = 500;
const _truncatedTotalLen = _maxLen + _suffixLen;

/// 对截断后的字符串的通用断言
Matcher _isTruncatedValue(String expectedPrefix) {
  return _TruncatedValueMatcher(expectedPrefix);
}

class _TruncatedValueMatcher extends Matcher {
  final String _expectedPrefix;
  const _TruncatedValueMatcher(this._expectedPrefix);

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! String) return false;
    return item.length == _truncatedTotalLen &&
        item.startsWith(_expectedPrefix) &&
        item.endsWith(_suffix);
  }

  @override
  Description describe(Description description) {
    return description.add(
      '长度为 $_truncatedTotalLen 的字符串（前缀 "${_expectedPrefix.substring(0, 10)}..." + "$_suffix"）',
    );
  }
}

void main() {
  // ── 纯字符串截断行为 ─────────────

  group('字符串截断', () {
    for (final tc in [
      ('短文本', false, '短文本'),
      ('边界 500 不截断', false, 'a' * 500),
      ('超长 600 截断', true, 'x' * 600),
      ('边界 501 截断', true, 'a' * 501),
    ]) {
      test(tc.$1, () {
        final result = truncateJsonValues(tc.$3);
        if (tc.$2) {
          expect(result, _isTruncatedValue(tc.$3.substring(0, _maxLen)));
        } else {
          expect(result, tc.$3);
        }
      });
    }
  });

  // ── 容器嵌套 ─────────────

  group('容器嵌套截断', () {
    test('Map 嵌套超长值', () {
      final input = <String, dynamic>{
        'a': '短',
        'b': 'x' * 600,
      };
      final result = truncateJsonValues(input) as Map<String, dynamic>;
      expect(result['a'], '短');
      expect(result['b'], _isTruncatedValue('x' * _maxLen));
    });

    test('List 元素截断', () {
      final input = <dynamic>['短', 'x' * 600];
      final result = truncateJsonValues(input) as List<dynamic>;
      expect(result[0], '短');
      expect(result[1], _isTruncatedValue('x' * _maxLen));
    });

    test('深层嵌套 Map 中的值也会被截断', () {
      final input = <String, dynamic>{
        'level1': <String, dynamic>{
          'level2': <String, dynamic>{
            'level3': 'x' * 600,
          },
        },
      };
      final result = truncateJsonValues(input) as Map<String, dynamic>;
      final level3 = (result['level1'] as Map<String, dynamic>)['level2']
          as Map<String, dynamic>?;
      expect(level3, isNotNull);
      expect(level3!['level3'], _isTruncatedValue('x' * _maxLen));
    });
  });

  // ── 非字符串类型 ─────────────

  test('非字符串值保持原样', () {
    final input = <String, dynamic>{
      'num': 123,
      'bool': true,
      'nullVal': null,
      'double': 3.14,
    };
    final result = truncateJsonValues(input) as Map<String, dynamic>;
    expect(result['num'], 123);
    expect(result['bool'], true);
    expect(result['nullVal'], isNull);
    expect(result['double'], 3.14);
  });

  test('顶层 null 输入返回 null', () {
    expect(truncateJsonValues(null), isNull);
  });

  // ── 真实 payload ─────────────

  test('真实 LLM payload 中只截断超长字段', () {
    final input = <String, dynamic>{
      'model': 'gpt-4',
      'messages': <dynamic>[
        <String, dynamic>{'role': 'system', 'content': 'x' * 600},
        <String, dynamic>{'role': 'user', 'content': 'hi'},
        <String, dynamic>{'role': 'assistant', 'content': 'ok'},
      ],
    };
    final result = truncateJsonValues(input) as Map<String, dynamic>;

    expect(result['model'], 'gpt-4');

    final messages = result['messages'] as List<dynamic>;
    expect(messages.length, 3);

    // system content 被截断
    final sysMsg = messages[0] as Map<String, dynamic>;
    expect(sysMsg['role'], 'system');
    expect(sysMsg['content'], _isTruncatedValue('x' * _maxLen));

    // user / assistant content 保持原样
    final userMsg = messages[1] as Map<String, dynamic>;
    expect(userMsg['role'], 'user');
    expect(userMsg['content'], 'hi');

    final asstMsg = messages[2] as Map<String, dynamic>;
    expect(asstMsg['role'], 'assistant');
    expect(asstMsg['content'], 'ok');
  });

  // ── 多字节字符截断 ─────────────

  group('多字节字符截断', () {
    test('CJK 长字符串截断后前缀正确', () {
      // 每个中文 1 个 UTF-16 code unit，500 个长度
      final cjk = '喵' * 600;
      final result = truncateJsonValues(cjk) as String;
      expect(result.length, equals(_truncatedTotalLen));
      expect(result.startsWith('喵' * _maxLen), isTrue);
      expect(result.endsWith(_suffix), isTrue);
    });

    test('emoji 截断不产生半个代理对', () {
      // 构造超过 maxLength 的 emoji 字符串（每个 emoji 是一个 grapheme cluster）
      final emoji = '😀' * 600; // 600 graphemes, 1200 code units
      expect(emoji.characters.length, equals(600));

      final result = truncateJsonValues(emoji) as String;
      expect(result.endsWith(_suffix), isTrue);

      // 截断后的前缀部分必须不含孤立代理对，能被 jsonEncode 正常编码
      final prefix = result.substring(0, result.length - _suffixLen);
      expect(() => jsonEncode(prefix), returnsNormally);
      // 保留前 500 个 grapheme（即 500 个完整 emoji，1000 code units）
      expect(prefix.characters.length, equals(_maxLen));
    });

    test('emoji 在边界处截断保持完整字符', () {
      // maxLength=500（默认），构造 501 个 emoji 触发截断
      final emoji = '😀' * 501; // 501 graphemes
      final result = truncateJsonValues(emoji) as String;
      final prefix = result.substring(0, result.length - _suffixLen);
      // 保留 500 个完整 emoji，无孤立代理对
      expect(prefix.characters.length, equals(_maxLen));
      expect(prefix, equals('😀' * _maxLen));
    });

    test('任意 maxLength 下截断都不切断 grapheme', () {
      // 用奇数 maxLength 验证不会在 surrogate pair 中间切断
      final emoji = '😀' * 600;
      final result = truncateJsonValues(emoji, maxLength: 251) as String;
      final suffix = '...[truncated]';
      expect(result.endsWith(suffix), isTrue);
      final prefix = result.substring(0, result.length - suffix.length);
      // 保留 251 个完整 emoji，可被正常 JSON 编码
      expect(prefix.characters.length, equals(251));
      expect(() => jsonEncode(prefix), returnsNormally);
    });
  });
}
