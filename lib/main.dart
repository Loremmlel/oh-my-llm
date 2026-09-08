import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'bootstrap.dart';

Future<void> main() async {
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  await bootstrap();
}
