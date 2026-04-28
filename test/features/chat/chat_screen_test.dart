import 'chat_screen/chat_screen_basics_cases.dart';
import 'chat_screen/chat_screen_branching_cases.dart';
import 'chat_screen/chat_screen_favorites_cases.dart';
import 'chat_screen/chat_screen_streaming_cases.dart';

void main() {
  registerChatScreenBasicsTests();
  registerChatScreenStreamingTests();
  registerChatScreenBranchingTests();
  registerChatScreenFavoritesTests();
}
