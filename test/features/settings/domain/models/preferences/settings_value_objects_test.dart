import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';

void main() {
  test('isAbnormalFinishReason classifies all documented categories', () {
    const cases = [
      (name: 'null', value: null, expected: false),
      (name: 'normal stop', value: 'stop', expected: false),
      (name: 'tool call', value: 'tool_calls', expected: false),
      (name: 'length', value: 'length', expected: true),
      (name: 'content filter', value: 'content_filter', expected: true),
      (name: 'unknown future value', value: 'unknown_reason', expected: true),
    ];

    for (final testCase in cases) {
      expect(
        isAbnormalFinishReason(testCase.value),
        testCase.expected,
        reason: testCase.name,
      );
    }
  });

  group('CustomHeadersConfig', () {
    test(
      'toHeaderMap trims keys, skips blanks, and keeps the last duplicate',
      () {
        const config = CustomHeadersConfig(
          headers: [
            CustomHeaderEntry(key: '', value: 'ignored'),
            CustomHeaderEntry(key: '  ', value: 'also ignored'),
            CustomHeaderEntry(key: ' X-Custom ', value: 'first'),
            CustomHeaderEntry(key: 'X-Custom', value: 'second'),
            CustomHeaderEntry(key: 'Authorization', value: 'Bearer token'),
          ],
        );

        expect(config.toHeaderMap(), {
          'X-Custom': 'second',
          'Authorization': 'Bearer token',
        });
      },
    );
  });
}
