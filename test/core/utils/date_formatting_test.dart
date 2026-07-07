import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/utils/date_formatting.dart';

void main() {
  group('formatDateOnly', () {
    for (final tc in [
      ('单位数月日零填充', DateTime(2026, 3, 5), '2026-03-05'),
      ('双位数月日不补', DateTime(2026, 12, 25), '2026-12-25'),
      ('年初', DateTime(2026, 1, 1), '2026-01-01'),
      ('年末', DateTime(2026, 12, 31), '2026-12-31'),
    ]) {
      test(tc.$1, () {
        expect(formatDateOnly(tc.$2), tc.$3);
      });
    }
  });

  group('formatDateTime', () {
    for (final tc in [
      ('单位数时分零填充', DateTime(2026, 3, 5, 8, 9), '2026-03-05 08:09'),
      ('双位数时分不补', DateTime(2026, 12, 25, 14, 30), '2026-12-25 14:30'),
      ('午夜', DateTime(2026, 1, 1, 0, 0), '2026-01-01 00:00'),
      ('深夜', DateTime(2026, 6, 15, 23, 59), '2026-06-15 23:59'),
    ]) {
      test(tc.$1, () {
        expect(formatDateTime(tc.$2), tc.$3);
      });
    }
  });
}
