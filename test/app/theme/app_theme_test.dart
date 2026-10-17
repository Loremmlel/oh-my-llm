import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';

void main() {
  test('浅色和深色主题可构建，默认字距与未指定字距都归零', () {
    for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
      expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
      expect(theme.textTheme.titleLarge?.letterSpacing, 0);
    }
  });
}
