import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/json_truncator.dart';

void main() {
  test('短字符串不截断', () {
    const input = '短文本';
    final result = truncateJsonValues(input);
    expect(result, input);
  });

  test('超长字符串截断', () {
    final input = 'x' * 600;
    final result = truncateJsonValues(input) as String;

    expect(result.length, 514);
    expect(result.endsWith('...[truncated]'), true);
    expect(result.substring(0, 500), 'x' * 500);
  });

  test('Map 嵌套超长值', () {
    final input = <String, dynamic>{
      'a': '短',
      'b': 'x' * 600,
    };
    final result = truncateJsonValues(input) as Map<String, dynamic>;

    expect(result['a'], '短');
    final b = result['b'] as String;
    expect(b.length, 514);
    expect(b.endsWith('...[truncated]'), true);
    expect(b.substring(0, 500), 'x' * 500);
  });

  test('List 元素截断', () {
    final input = <dynamic>['短', 'x' * 600];
    final result = truncateJsonValues(input) as List<dynamic>;

    expect(result[0], '短');
    final second = result[1] as String;
    expect(second.length, 514);
    expect(second.endsWith('...[truncated]'), true);
    expect(second.substring(0, 500), 'x' * 500);
  });

  test('非字符串值原样', () {
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

  test('深层嵌套 Map', () {
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
    final s = level3!['level3'] as String;
    expect(s.length, 514);
    expect(s.endsWith('...[truncated]'), true);
    expect(s.substring(0, 500), 'x' * 500);
  });

  test('边界值 500 不截断', () {
    final input = 'a' * 500;
    final result = truncateJsonValues(input) as String;

    expect(result, input);
    expect(result.length, 500);
    expect(result.endsWith('...[truncated]'), false);
  });

  test('边界值 501 截断', () {
    final input = 'a' * 501;
    final result = truncateJsonValues(input) as String;

    expect(result.length, 514);
    expect(result.endsWith('...[truncated]'), true);
    expect(result.substring(0, 500), 'a' * 500);
  });

  test('真实 LLM payload', () {
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
    final sysContent = sysMsg['content'] as String;
    expect(sysContent.length, 514);
    expect(sysContent.endsWith('...[truncated]'), true);
    expect(sysContent.substring(0, 500), 'x' * 500);

    // user content 保持原样
    final userMsg = messages[1] as Map<String, dynamic>;
    expect(userMsg['role'], 'user');
    expect(userMsg['content'], 'hi');

    // assistant content 保持原样
    final asstMsg = messages[2] as Map<String, dynamic>;
    expect(asstMsg['role'], 'assistant');
    expect(asstMsg['content'], 'ok');
  });
}
