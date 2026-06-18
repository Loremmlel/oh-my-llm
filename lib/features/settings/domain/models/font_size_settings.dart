import 'package:equatable/equatable.dart';

/// 正文字号全局设置。
class FontSizeSettings extends Equatable {
  const FontSizeSettings({
    this.bodyFontSize = 14,
  });

  /// 正文字号，范围 12-24，默认 14（M3 bodyMedium 默认值）。
  final double bodyFontSize;

  FontSizeSettings copyWith({double? bodyFontSize}) {
    return FontSizeSettings(bodyFontSize: bodyFontSize ?? this.bodyFontSize);
  }

  Map<String, dynamic> toJson() {
    return {'bodyFontSize': bodyFontSize};
  }

  factory FontSizeSettings.fromJson(Map<String, dynamic> json) {
    return FontSizeSettings(
      bodyFontSize: (json['bodyFontSize'] as num?)?.toDouble() ?? 14,
    );
  }

  @override
  List<Object?> get props => [bodyFontSize];
}
