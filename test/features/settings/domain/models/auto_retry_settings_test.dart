import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';

void main() {
  group('AutoRetrySettings', () {
    test('copyWith clearMaxJitterSeconds 重置为默认值 15', () {
      const settings = AutoRetrySettings(maxJitterSeconds: 30);
      final cleared = settings.copyWith(clearMaxJitterSeconds: true);
      expect(cleared.maxJitterSeconds, 15);
    });

    test('copyWith clearMaxRetryCount 重置为默认值 0', () {
      const settings = AutoRetrySettings(maxRetryCount: 5);
      final cleared = settings.copyWith(clearMaxRetryCount: true);
      expect(cleared.maxRetryCount, 0);
    });

    test('copyWith clearRetryMode 重置为 perMinuteWindow', () {
      const settings = AutoRetrySettings(retryMode: RetryMode.fixedInterval);
      final cleared = settings.copyWith(clearRetryMode: true);
      expect(cleared.retryMode, RetryMode.perMinuteWindow);
    });

    test('fromJson 对未知 retryMode 回退到 perMinuteWindow', () {
      final settings = AutoRetrySettings.fromJson({
        'maxJitterSeconds': 20,
        'maxRetryCount': 3,
        'retryMode': 'unknownMode',
      });
      expect(settings.retryMode, RetryMode.perMinuteWindow);
      expect(settings.maxJitterSeconds, 20);
      expect(settings.maxRetryCount, 3);
    });

    test('fromJson 缺失字段使用默认值', () {
      final settings = AutoRetrySettings.fromJson({});
      expect(settings.maxJitterSeconds, 15);
      expect(settings.maxRetryCount, 0);
      expect(settings.retryMode, RetryMode.perMinuteWindow);
    });

    test('toJson → fromJson round-trip', () {
      const settings = AutoRetrySettings(
        maxJitterSeconds: 10,
        maxRetryCount: 3,
        retryMode: RetryMode.fixedInterval,
      );
      final restored = AutoRetrySettings.fromJson(settings.toJson());
      expect(restored, settings);
    });
  });
}
