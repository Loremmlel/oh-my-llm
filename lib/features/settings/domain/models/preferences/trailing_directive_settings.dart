import 'package:equatable/equatable.dart';

/// 末尾指令的全局配置。
class TrailingDirectiveSettings extends Equatable {
  const TrailingDirectiveSettings({
    this.content = '',
    this.alternatingMode = false,
  });

  /// 追加为倒数第一条用户消息的固定指令文本。
  final String content;

  /// 是否启用轮替模式：在本次输入末尾拼接过渡提示并插入助手"明白"消息。
  final bool alternatingMode;

  bool get hasContent => content.trim().isNotEmpty;

  TrailingDirectiveSettings copyWith({String? content, bool? alternatingMode}) {
    return TrailingDirectiveSettings(
      content: content ?? this.content,
      alternatingMode: alternatingMode ?? this.alternatingMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {'content': content, 'alternatingMode': alternatingMode};
  }

  factory TrailingDirectiveSettings.fromJson(Map<String, dynamic> json) {
    return TrailingDirectiveSettings(
      content: json['content'] as String? ?? '',
      alternatingMode: json['alternatingMode'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [content, alternatingMode];
}
