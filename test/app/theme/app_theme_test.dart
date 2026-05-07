import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/theme/app_theme.dart';

void main() {
  test('light and dark themes both expose app bar overlay styles', () {
    expect(AppTheme.lightTheme.appBarTheme.systemOverlayStyle, isNotNull);
    expect(AppTheme.darkTheme.appBarTheme.systemOverlayStyle, isNotNull);
  });
}
