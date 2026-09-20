import 'dart:convert';
import 'dart:typed_data';

import 'package:oh_my_llm/features/chat/application/ports/chat_image_source.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_image_store.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_image_attachment.dart';

final testImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);
final testChatImage = ChatImageAttachment(
  id: 'a' * 64,
  name: '测试图片.png',
  mimeType: 'image/png',
  byteLength: testImageBytes.length,
  width: 1,
  height: 1,
);

class TestChatImageStore implements ChatImageStore {
  bool missing = false;
  @override
  Future<ChatImageAttachment> importImage(
    Uint8List bytes, {
    required String name,
  }) async => testChatImage;
  @override
  Future<Uint8List> read(String id) async {
    if (missing) throw const FormatException('图片文件已丢失');
    return testImageBytes;
  }
}

class TestChatImageSource implements ChatImageSource {
  Future<List<SelectedChatImage>> Function()? pick;
  SelectedChatImage? clipboard;
  @override
  Future<List<SelectedChatImage>> pickImages() async => pick == null
      ? [(name: testChatImage.name, bytes: testImageBytes)]
      : await pick!();
  @override
  Future<SelectedChatImage?> readClipboardImage() async => clipboard;
}
