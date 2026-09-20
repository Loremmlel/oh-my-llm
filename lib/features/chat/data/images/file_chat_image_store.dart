import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:oh_my_llm/core/llm/llm_input_content.dart';

import '../../application/ports/chat_image_store.dart';
import '../../domain/models/chat_image_attachment.dart';

/// 文件先完整落盘才把引用交给草稿；内容哈希允许消息分支安全复用原图。
class FileChatImageStore implements ChatImageStore {
  FileChatImageStore(this.directory);
  final Directory directory;
  static const maxImportBytes = 20 * 1024 * 1024;

  File _file(String id) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('图片引用无效');
    }
    return File('${directory.path}${Platform.pathSeparator}$id');
  }

  @override
  Future<ChatImageAttachment> importImage(
    Uint8List bytes, {
    required String name,
  }) async {
    if (bytes.isEmpty || bytes.length > maxImportBytes) {
      throw const FormatException('图片为空或超过 20 MiB，请选择较小的图片');
    }
    final prepared = await Isolate.run(() => _prepareImage(bytes));
    final id = sha256.convert(prepared.bytes).toString();
    await directory.create(recursive: true);
    final file = _file(id);
    final temporary = await directory.createTemp('.import-');
    try {
      final pending = File('${temporary.path}${Platform.pathSeparator}image');
      await pending.writeAsBytes(prepared.bytes, flush: true);
      // 同一内容始终落到同一文件；重新添加也可修复被外部损坏的文件。
      await pending.rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
    return ChatImageAttachment(
      id: id,
      name: name.split(RegExp(r'[/\\]')).last,
      mimeType: prepared.mimeType,
      byteLength: prepared.bytes.length,
      width: prepared.width,
      height: prepared.height,
    );
  }

  @override
  Future<Uint8List> read(String id) async {
    final file = _file(id);
    if (!await file.exists()) {
      throw const FormatException('图片文件已丢失，请重新添加图片，或将这条消息从发送上下文中排除');
    }
    if (await file.length() > LlmImagePart.maxBytes) {
      throw const FormatException('图片文件超过大小限制');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > LlmImagePart.maxBytes ||
        sha256.convert(bytes).toString() != id) {
      throw const FormatException('图片文件已损坏，请重新添加图片');
    }
    return bytes;
  }
}

({Uint8List bytes, String mimeType, int width, int height}) _prepareImage(
  Uint8List bytes,
) {
  try {
    return _decodeImage(bytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('图片无法解码，请重新选择');
  }
}

({Uint8List bytes, String mimeType, int width, int height}) _decodeImage(
  Uint8List bytes,
) {
  if (bytes.length < 12) throw const FormatException('图片无法解码，请重新选择');
  final decoder = <img.Decoder>[
    img.PngDecoder(),
    img.JpegDecoder(),
    img.GifDecoder(),
    img.WebPDecoder(),
  ].where((decoder) => decoder.isValidFile(bytes)).firstOrNull;
  if (decoder is! img.PngDecoder &&
      decoder is! img.JpegDecoder &&
      decoder is! img.GifDecoder &&
      decoder is! img.WebPDecoder) {
    throw const FormatException('仅支持 JPEG、PNG、GIF 和 WebP 图片');
  }
  final info = decoder!.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 32 * 1024 * 1024) {
    throw const FormatException('图片无法解码或分辨率过大，请选择不超过 3200 万像素的图片');
  }
  final frame = decoder.decodeFrame(0);
  if (frame == null) throw const FormatException('图片无法解码，请重新选择');
  var image = img.bakeOrientation(frame);
  if (image.width > 2048 || image.height > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
    );
  }
  final jpeg = decoder is img.JpegDecoder;
  final encoded = Uint8List.fromList(
    jpeg ? img.encodeJpg(image, quality: 90) : img.encodePng(image),
  );
  if (encoded.length > LlmImagePart.maxBytes) {
    throw const FormatException('处理后的图片超过 4 MiB，请缩小图片后重试');
  }
  return (
    bytes: encoded,
    mimeType: jpeg ? 'image/jpeg' : 'image/png',
    width: image.width,
    height: image.height,
  );
}
