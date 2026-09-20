import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SelectedChatImage = ({String name, Uint8List bytes});

abstract interface class ChatImageSource {
  Future<List<SelectedChatImage>> pickImages();
  Future<SelectedChatImage?> readClipboardImage();
}

final chatImageSourceProvider = Provider<ChatImageSource>((ref) {
  throw StateError('ChatImageSource 尚未由应用组合层绑定');
});
