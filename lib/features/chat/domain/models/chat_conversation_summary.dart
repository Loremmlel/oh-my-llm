import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

/// 历史页使用的会话摘要，只保留列表渲染所需的轻量字段。
class ChatConversationSummary extends Equatable {
  const ChatConversationSummary({
    required this.id,
    required this.updatedAt,
    this.title,
    this.firstUserMessagePreview = '',
    this.latestUserMessagePreview = '',
  });

  final String id;
  final String? title;
  final DateTime updatedAt;
  final String firstUserMessagePreview;
  final String latestUserMessagePreview;

  /// 是否存在用户手动设置的标题。
  bool get hasCustomTitle => title != null && title!.trim().isNotEmpty;

  /// 优先显示显式标题；否则回退到首条用户消息的前 15 个字符。
  String get resolvedTitle {
    if (hasCustomTitle) {
      return title!.trim();
    }

    final normalizedPreview = firstUserMessagePreview.trim();
    if (normalizedPreview.isEmpty) {
      return '未命名对话';
    }

    return normalizedPreview.characters.take(15).toString();
  }

  /// 列表中展示的预览文本，优先取最新用户消息。
  String get previewText {
    final normalizedPreview = latestUserMessagePreview.trim();
    if (normalizedPreview.isNotEmpty) {
      return normalizedPreview.replaceAll('\n', ' ');
    }

    final normalizedFirstPreview = firstUserMessagePreview.trim();
    if (normalizedFirstPreview.isNotEmpty) {
      return normalizedFirstPreview.replaceAll('\n', ' ');
    }

    return resolvedTitle;
  }

  @override
  List<Object?> get props => [
    id,
    title,
    updatedAt,
    firstUserMessagePreview,
    latestUserMessagePreview,
  ];
}
