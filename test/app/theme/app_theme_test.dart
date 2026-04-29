import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/theme/app_theme.dart';

void main() {
  test('light theme uses dark status bar icons with transparent bar', () {
    final style = AppTheme.lightTheme.appBarTheme.systemOverlayStyle;

    expect(style, isNotNull);
    expect(style!.statusBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
  });

  test('dark theme uses light status bar icons with transparent bar', () {
    final style = AppTheme.darkTheme.appBarTheme.systemOverlayStyle;

    expect(style, isNotNull);
    expect(style!.statusBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });
}
