import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/json_truncator.dart';

const _suffix = '...[truncated]';
const _maxLen = 500;

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
          expect(result, '${tc.$3.substring(0, _maxLen)}$_suffix');
        } else {
          expect(result, tc.$3);
        }
      });
    }
  });

  // ── 容器嵌套 ─────────────

  test('递归截断 Map 与 List 中的长文本，保留短文本和非字符串值', () {
    final input = {
      'text': 'x' * 600,
      'nested': [
        '短',
        'x' * 600,
        {
          'deeper': {'text': 'x' * 600},
        },
      ],
      'number': 123,
      'bool': true,
      'null': null,
      'double': 3.14,
    };
    final truncated = '${'x' * _maxLen}$_suffix';
    expect(truncateJsonValues(input), {
      'text': truncated,
      'nested': [
        '短',
        truncated,
        {
          'deeper': {'text': truncated},
        },
      ],
      'number': 123,
      'bool': true,
      'null': null,
      'double': 3.14,
    });
    expect(truncateJsonValues(null), isNull);
  });

  // ── 多字节字符截断 ─────────────

  test('默认和自定义长度均按完整 grapheme 截断 emoji', () {
    expect(truncateJsonValues('😀' * 501), '${'😀' * 500}$_suffix');
    expect(
      truncateJsonValues('😀' * 600, maxLength: 251),
      '${'😀' * 251}$_suffix',
    );
  });
}
