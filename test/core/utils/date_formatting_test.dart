import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/date_formatting.dart';

void main() {
  test('日期格式保留双位数并对单位数月日补零', () {
    for (final tc in [
      ('单位数月日零填充', DateTime(2026, 3, 5), '2026-03-05'),
      ('双位数月日不补', DateTime(2026, 12, 25), '2026-12-25'),
    ]) {
      expect(formatDateOnly(tc.$2), tc.$3, reason: tc.$1);
    }
  });

  test('日期时间格式对月日时分补零并正确表示午夜', () {
    for (final tc in [
      ('单位数时分零填充', DateTime(2026, 3, 5, 8, 9), '2026-03-05 08:09'),
      ('双位数时分不补', DateTime(2026, 12, 25, 14, 30), '2026-12-25 14:30'),
      ('午夜', DateTime(2026, 1, 1, 0, 0), '2026-01-01 00:00'),
    ]) {
      expect(formatDateTime(tc.$2), tc.$3, reason: tc.$1);
    }
  });
}
