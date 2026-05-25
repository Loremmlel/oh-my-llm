import 'package:flutter_test/flutter_test.dart';

/// 验证 Finder 找到的 Widget 数量在指定范围内。
Matcher findsBetween(int min, int max) => _FindsBetweenMatcher(min, max);

class _FindsBetweenMatcher extends Matcher {
  final int _min;
  final int _max;

  const _FindsBetweenMatcher(this._min, this._max);

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! int) return false;
    return item >= _min && item <= _max;
  }

  @override
  Description describe(Description description) {
    return description.add('finds between $_min and $_max widgets');
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! int) {
      return mismatchDescription.add('is not an int');
    }
    return mismatchDescription.add('finds $item widgets');
  }
}
