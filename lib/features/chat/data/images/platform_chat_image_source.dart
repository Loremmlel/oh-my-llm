import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../application/ports/chat_image_source.dart';
import '../../domain/models/chat_image_attachment.dart';
import 'file_chat_image_store.dart';

class PlatformChatImageSource implements ChatImageSource {
  @override
  Future<List<SelectedChatImage>> pickImages() async {
    final files = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: '添加图片',
    );
    if (files.length > ChatImageAttachment.maxPerMessage) {
      throw const FormatException('每条消息最多添加 8 张图片');
    }
    final selected = <SelectedChatImage>[];
    for (final file in files) {
      final length = await file.length();
      if (length == null || length > FileChatImageStore.maxImportBytes) {
        throw const FormatException('无法读取图片或图片超过 20 MiB');
      }
      selected.add((name: file.name, bytes: await file.readAsBytes()));
    }
    return selected;
  }

  @override
  Future<SelectedChatImage?> readClipboardImage() async {
    final bytes = await Pasteboard.image;
    return bytes == null ? null : (name: '粘贴的图片', bytes: bytes);
  }
}
