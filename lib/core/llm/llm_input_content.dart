import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'llm_event.dart';

sealed class LlmContentPart extends Equatable {
  const LlmContentPart();
}

final class LlmTextPart extends LlmContentPart {
  const LlmTextPart(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

/// 只持有本次调用的图片字节，不携带文件路径或厂商 Files API 身份。
final class LlmImagePart extends LlmContentPart {
  LlmImagePart({required this.mimeType, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!supportedMimeTypes.contains(mimeType) ||
        bytes.isEmpty ||
        bytes.length > maxBytes) {
      throw const LlmException(
        '图片必须为 JPEG、PNG、GIF 或 WebP，且不超过 4 MiB',
        kind: LlmFailureKind.invalidRequest,
      );
    }
  }

  static const supportedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  };
  // 留出 base64 膨胀空间，也适用于采用更小请求上限的兼容服务。
  static const maxBytes = 4 * 1024 * 1024;
  static const maxRequestBytes = 20 * 1024 * 1024;
  final String mimeType;
  final Uint8List bytes;
  String get base64Data => base64Encode(bytes);
  String get dataUrl => 'data:$mimeType;base64,$base64Data';
  @override
  List<Object?> get props => [mimeType, bytes];
  @override
  String toString() => 'LlmImagePart($mimeType, ${bytes.length} bytes)';
}
