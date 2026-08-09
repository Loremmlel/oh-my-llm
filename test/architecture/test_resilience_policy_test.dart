import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 保持测试树免受脆弱等待与内部 Finder 回流。
///
/// 扫描器先用词法状态机把注释与字符串内容替换为空白（保留换行），
/// 再对剩余代码计数，避免 URL、转义引号或多行字符串破坏匹配。
/// 待查 token 用字符串片段拼接，形成门禁自身的第二层自匹配保护。
void main() {
  group('扫描器', () {
    test('注释与字符串内容不计数', () {
      const source = '''
// find.byKey 藏在行注释里
/* pumpAndSettle 藏在块注释里 */
final s = 'Future.delayed(Duration.zero)';
find.byKey(const Key('x'));
Future.delayed(Duration.zero);
''';
      final masked = _maskCommentsAndStrings(source);
      expect(_countOf(masked, _findByKeyPattern), 1);
      expect(_countOf(masked, _futureDelayedPattern), 1);
      expect(_countOf(masked, _settlePattern), 0);
    });

    test('泛型与非泛型延时都计数，多行 pump 可识别', () {
      const source = '''
Future.delayed(Duration.zero);
Future<void>.delayed(const Duration(seconds: 1));
tester
    .pump(
      const Duration(milliseconds: 300),
    );
''';
      final masked = _maskCommentsAndStrings(source);
      expect(_countOf(masked, _futureDelayedPattern), 2);
      expect(_countOf(masked, _literalMsPumpPattern), 1);
    });

    test('未登记路径出现违规会被拒绝', () {
      expect(
        () => _verifyExactAllow(
          const {'fake/path.dart': 1},
          _settleAllow,
          'pumpAndSettle',
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('登记路径不再出现违规时陈旧豁免会被拒绝', () {
      expect(
        () => _verifyExactAllow(const <String, int>{}, const {
          'fake/path.dart': 1,
        }, 'pumpAndSettle'),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('仓库门禁', () {
    test('整个 test 树满足韧性契约', () async {
      final rawSettleCounts = <String, int>{};
      final delayedCounts = <String, int>{};
      final otherViolations = <String>[];

      await for (final entity in Directory('test').list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final masked = _maskCommentsAndStrings(await entity.readAsString());

        final settleCount = _countOf(masked, _settlePattern);
        if (settleCount > 0) rawSettleCounts[path] = settleCount;
        final delayedCount = _countOf(masked, _futureDelayedPattern);
        if (delayedCount > 0) delayedCounts[path] = delayedCount;

        if (_countOf(masked, _findByKeyPattern) > 0) {
          otherViolations.add('$path: find.byKey');
        }
        if (_countOf(masked, _chunkProbe) > 0) {
          otherViolations.add('$path: chunkDelay');
        }
        if (_countOf(masked, _debounceMarginPattern) > 0) {
          otherViolations.add('$path: debounce 加余量');
        }
        if (_countOf(masked, _literalMsPumpPattern) > 0) {
          otherViolations.add('$path: 魔法毫秒 pump');
        }
      }

      _verifyExactAllow(rawSettleCounts, _settleAllow, 'pumpAndSettle');
      _verifyExactAllow(delayedCounts, _futureDelayedAllow, 'Future.delayed');
      expect(
        otherViolations,
        isEmpty,
        reason: '违规项:\n${otherViolations.join('\n')}',
      );
    });
  });
}

/// 允许直接 pumpAndSettle 的唯一位置，精确 1 处。
const _settleAllow = {'test/helpers/widget_test_animation.dart': 1};

/// 允许真实延时的位置（外部 socket 资源释放与负向观测，
/// 已有 udp tag 且 CI 排除），按精确数量登记。
const _futureDelayedAllow = {
  'test/features/sync/data/sync_udp_discovery_test.dart': 3,
};

// 待查 token 均以片段拼接，避免门禁自身被匹配
final _findByKeyPattern = RegExp(
  r'find\.by'
  'Key',
);
final _settlePattern = RegExp(
  'pump'
  'AndSettle',
);
final _futureDelayedPattern = RegExp(
  r'Future(?:<[^>]+>)?\.'
  'delayed',
);
final _chunkProbe = RegExp(
  'chunk'
  'Delay',
);
final _debounceMarginPattern = RegExp(
  'search'
  'Debounce'
  r'\s*\+|variable'
  'Reconcile'
  r'Debounce\s*\+',
);
final _literalMsPumpPattern = RegExp(
  r'tester\s*\.\s*pump\s*\(\s*(?:const\s+)?Duration\s*\(\s*milliseconds\s*:\s*\d+',
  multiLine: true,
);

/// 精确 allowlist 校验：少于允许数量也失败，防止陈旧豁免永远保留。
void _verifyExactAllow(
  Map<String, int> actual,
  Map<String, int> allow,
  String token,
) {
  final excess = actual.entries
      .where((e) => allow[e.key] != e.value)
      .map((e) => '${e.key}: ${e.value} 处 $token（允许 ${allow[e.key] ?? 0}）')
      .join('\n');
  expect(excess, isEmpty, reason: '超出或缺失的豁免:\n$excess');
  final missing = allow.keys.where((k) => !actual.containsKey(k)).toList();
  expect(missing, isEmpty, reason: '豁免路径未出现（陈旧豁免）:\n$missing');
}

int _countOf(String masked, RegExp pattern) =>
    pattern.allMatches(masked).length;

/// 把注释与字符串内容替换为空白，保留换行与其余字符。
String _maskCommentsAndStrings(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    final isSlash = char == '/';
    if (isSlash && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        buffer.write(' ');
        i++;
      }
    } else if (isSlash && i + 1 < source.length && source[i + 1] == '*') {
      buffer.write('  ');
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        buffer.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i + 1 < source.length) {
        buffer.write('  ');
        i += 2;
      }
    } else if (char == "'" || char == '"') {
      final quote = char;
      // 原始字符串 r'...' 中反斜杠是字面量而非转义前缀：若混为一谈，
      // r'\' 这类以反斜杠结尾的写法会让转义分支吞掉结束引号，其后的
      // 字符串全部错位漏掩码。这里用前导 r 识别原始字符串，内部不处理转义。
      final isRaw = i > 0 && source[i - 1] == 'r';
      buffer.write(' ');
      i++;
      var triple = false;
      if (i + 1 < source.length &&
          source[i] == quote &&
          source[i + 1] == quote) {
        triple = true;
        buffer.write('  ');
        i += 2;
      }
      while (i < source.length) {
        if (!isRaw && source[i] == r'\' && i + 1 < source.length) {
          buffer.write('  ');
          i += 2;
        } else if (source[i] == quote) {
          if (triple) {
            if (i + 2 < source.length &&
                source[i + 1] == quote &&
                source[i + 2] == quote) {
              buffer.write('   ');
              i += 3;
              break;
            }
            buffer.write(' ');
            i++;
          } else {
            buffer.write(' ');
            i++;
            break;
          }
        } else {
          buffer.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
    } else {
      buffer.write(char);
      i++;
    }
  }
  return buffer.toString();
}
