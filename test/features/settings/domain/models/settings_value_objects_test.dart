import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/chat_defaults.dart';
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

void main() {
  group('AutoRetrySettings', () {
    test('each clear flag resets only its selected setting', () {
      const settings = AutoRetrySettings(
        maxJitterSeconds: 30,
        maxRetryCount: 5,
        retryMode: RetryMode.fixedInterval,
        retryOnAbnormalFinishReason: true,
        retryOnTimeout: true,
        timeoutSeconds: 90,
      );

      final cases = [
        (
          name: 'max jitter',
          field: 'maxJitterSeconds',
          defaultValue: 15,
          actual: settings.copyWith(clearMaxJitterSeconds: true),
        ),
        (
          name: 'max retry count',
          field: 'maxRetryCount',
          defaultValue: 0,
          actual: settings.copyWith(clearMaxRetryCount: true),
        ),
        (
          name: 'retry mode',
          field: 'retryMode',
          defaultValue: RetryMode.perMinuteWindow.name,
          actual: settings.copyWith(clearRetryMode: true),
        ),
        (
          name: 'abnormal finish reason',
          field: 'retryOnAbnormalFinishReason',
          defaultValue: false,
          actual: settings.copyWith(clearRetryOnAbnormalFinishReason: true),
        ),
        (
          name: 'timeout retry',
          field: 'retryOnTimeout',
          defaultValue: false,
          actual: settings.copyWith(clearRetryOnTimeout: true),
        ),
        (
          name: 'timeout seconds',
          field: 'timeoutSeconds',
          defaultValue: 30,
          actual: settings.copyWith(clearTimeoutSeconds: true),
        ),
      ];

      for (final testCase in cases) {
        expect(testCase.actual.toJson(), {
          ...settings.toJson(),
          testCase.field: testCase.defaultValue,
        }, reason: testCase.name);
      }
    });

    test('missing fields and an unknown mode use documented defaults', () {
      expect(AutoRetrySettings.fromJson({}), const AutoRetrySettings());

      final settings = AutoRetrySettings.fromJson({
        'maxJitterSeconds': 20,
        'maxRetryCount': 3,
        'retryMode': 'unknownMode',
      });
      expect(settings.maxJitterSeconds, 20);
      expect(settings.maxRetryCount, 3);
      expect(settings.retryMode, RetryMode.perMinuteWindow);
      expect(settings.retryOnAbnormalFinishReason, isFalse);
      expect(settings.retryOnTimeout, isFalse);
      expect(settings.timeoutSeconds, 30);
    });

    test('JSON round-trip preserves every setting', () {
      const settings = AutoRetrySettings(
        maxJitterSeconds: 10,
        maxRetryCount: 3,
        retryMode: RetryMode.fixedInterval,
        retryOnAbnormalFinishReason: true,
        retryOnTimeout: true,
        timeoutSeconds: 45,
      );

      expect(AutoRetrySettings.fromJson(settings.toJson()), settings);
    });
  });

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

  group('ChatDefaults', () {
    test('clear flags affect only the selected default', () {
      const defaults = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: 'preset-1',
      );

      expect(
        defaults.copyWith(clearDefaultModelId: true),
        const ChatDefaults(defaultPresetPromptId: 'preset-1'),
      );
      expect(
        defaults.copyWith(clearDefaultPresetPromptId: true),
        const ChatDefaults(defaultModelId: 'model-1'),
      );
    });

    test('missing JSON fields default to null', () {
      expect(ChatDefaults.fromJson({}), const ChatDefaults());
    });

    test('JSON round-trip preserves nullable selections', () {
      const defaults = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: null,
      );

      expect(ChatDefaults.fromJson(defaults.toJson()), defaults);
    });
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

    test('missing headers and entry fields use empty defaults', () {
      expect(CustomHeadersConfig.fromJson({}).headers, isEmpty);
      expect(
        CustomHeaderEntry.fromJson({}),
        const CustomHeaderEntry(key: '', value: ''),
      );
    });

    test('JSON round-trip preserves ordered entries', () {
      const config = CustomHeadersConfig(
        headers: [
          CustomHeaderEntry(key: 'X-A', value: '1'),
          CustomHeaderEntry(key: 'X-B', value: '2'),
        ],
      );

      expect(CustomHeadersConfig.fromJson(config.toJson()), config);
    });
  });

  group('FontSizeSettings', () {
    test('missing or non-number JSON values default to 14', () {
      for (final testCase in [
        (name: 'missing', json: <String, dynamic>{}),
        (name: 'wrong type', json: <String, dynamic>{'bodyFontSize': '18'}),
      ]) {
        expect(
          FontSizeSettings.fromJson(testCase.json).bodyFontSize,
          14,
          reason: testCase.name,
        );
      }
    });

    test('JSON round-trip preserves a non-default size', () {
      const settings = FontSizeSettings(bodyFontSize: 20);
      expect(FontSizeSettings.fromJson(settings.toJson()), settings);
    });
  });

  group('OutputProcessingSettings', () {
    test('OutputRegexRule round-trip preserves every field', () {
      const rule = OutputRegexRule(
        id: 'rule-1',
        title: '过滤极其',
        pattern: '极其',
        replacement: '非常',
        order: 3,
        enabled: false,
      );

      expect(OutputRegexRule.fromJson(rule.toJson()), rule);
    });

    test('OutputRegexRule missing fields use documented defaults', () {
      final rule = OutputRegexRule.fromJson({'id': 'only-id'});
      expect(rule.id, 'only-id');
      expect(rule.title, '');
      expect(rule.pattern, '');
      expect(rule.replacement, '');
      expect(rule.order, 0);
      expect(rule.enabled, isTrue);
    });

    test('settings round-trip preserves rule order', () {
      const settings = OutputProcessingSettings(
        rules: [
          OutputRegexRule(id: 'r1', pattern: 'a', order: 0),
          OutputRegexRule(id: 'r2', pattern: 'b', order: 1),
        ],
      );

      expect(OutputProcessingSettings.fromJson(settings.toJson()), settings);
    });

    test('a non-list rules value falls back to an empty list', () {
      expect(
        OutputProcessingSettings.fromJson({'rules': 'oops'}).rules,
        isEmpty,
      );
    });
  });
}
