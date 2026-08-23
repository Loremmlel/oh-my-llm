import 'history_screen/history_screen_actions_cases.dart';
import 'history_screen/history_screen_async_query_cases.dart';
import 'history_screen/history_screen_pagination_bar_cases.dart';
import 'history_screen/history_screen_responsive_cases.dart';
import 'history_screen/history_screen_search_cases.dart';

void main() {
  registerHistoryScreenSearchTests();
  registerHistoryScreenActionsTests();
  registerHistoryScreenAsyncQueryTests();
  registerHistoryScreenPaginationBarTests();
  registerHistoryScreenResponsiveTests();
}
