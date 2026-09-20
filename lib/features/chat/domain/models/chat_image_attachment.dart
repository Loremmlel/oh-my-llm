import 'package:equatable/equatable.dart';

/// 聊天记录只保存应用私有图片文件的身份与展示元数据。
class ChatImageAttachment extends Equatable {
  const ChatImageAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
  });

  static const maxPerMessage = 8;
  final String id;
  final String name;
  final String mimeType;
  final int byteLength;
  final int width;
  final int height;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'byteLength': byteLength,
    'width': width,
    'height': height,
  };

  factory ChatImageAttachment.fromJson(Map<String, dynamic> json) {
    final image = ChatImageAttachment(
      id: json['id'] as String,
      name: json['name'] as String,
      mimeType: json['mimeType'] as String,
      byteLength: json['byteLength'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
    );
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(image.id) ||
        !{
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        }.contains(image.mimeType) ||
        image.byteLength <= 0 ||
        image.width <= 0 ||
        image.height <= 0) {
      throw const FormatException('图片引用无效');
    }
    return image;
  }

  @override
  List<Object?> get props => [id, name, mimeType, byteLength, width, height];
}
