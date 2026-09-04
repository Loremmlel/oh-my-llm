import 'package:flutter_test/flutter_test.dart';

/// 推进到 StreamMarkdown 的下一次固定刷新窗口。
const streamMarkdownRefreshInterval = Duration(milliseconds: 50);

Future<void> pumpStreamMarkdownRefresh(WidgetTester tester) {
  return tester.pump(streamMarkdownRefreshInterval);
}
