import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_image_attachment.dart';

abstract interface class ChatImageStore {
  Future<ChatImageAttachment> importImage(
    Uint8List bytes, {
    required String name,
  });
  Future<Uint8List> read(String id);
}

final chatImageStoreProvider = Provider<ChatImageStore>((ref) {
  throw StateError('ChatImageStore 尚未由应用组合层绑定');
});

final chatImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, id) {
      return ref.watch(chatImageStoreProvider).read(id);
    });
