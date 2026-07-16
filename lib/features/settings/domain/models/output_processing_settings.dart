import 'package:equatable/equatable.dart';

/// 单条输出正则处理规则。
///
/// 在模型回复正文（content）落盘/展示前，按 [order] 升序依次应用。
/// [replacement] 为空表示删除匹配到的内容；非空则替换为该字符串。
class OutputRegexRule extends Equatable {
  const OutputRegexRule({
    required this.id,
    this.title = '',
    this.pattern = '',
    this.replacement = '',
    this.order = 0,
    this.enabled = true,
  });

  /// 规则唯一 ID。
  final String id;

  /// 规则标题，仅用于展示与区分。
  final String title;

  /// 正则表达式。
  final String pattern;

  /// 替换字符串，空字符串表示删除匹配内容。
  final String replacement;

  /// 应用顺序，升序。
  final int order;

  /// 是否启用。
  final bool enabled;

  OutputRegexRule copyWith({
    String? id,
    String? title,
    String? pattern,
    String? replacement,
    int? order,
    bool? enabled,
  }) {
    return OutputRegexRule(
      id: id ?? this.id,
      title: title ?? this.title,
      pattern: pattern ?? this.pattern,
      replacement: replacement ?? this.replacement,
      order: order ?? this.order,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'pattern': pattern,
      'replacement': replacement,
      'order': order,
      'enabled': enabled,
    };
  }

  factory OutputRegexRule.fromJson(Map<String, dynamic> json) {
    return OutputRegexRule(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      replacement: json['replacement'] as String? ?? '',
      order: (json['order'] as int?) ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [id, title, pattern, replacement, order, enabled];
}

/// 输出处理的全局设置：一组正则规则。
class OutputProcessingSettings extends Equatable {
  const OutputProcessingSettings({this.rules = const []});

  final List<OutputRegexRule> rules;

  OutputProcessingSettings copyWith({List<OutputRegexRule>? rules}) {
    return OutputProcessingSettings(rules: rules ?? this.rules);
  }

  Map<String, dynamic> toJson() {
    return {'rules': rules.map((rule) => rule.toJson()).toList()};
  }

  factory OutputProcessingSettings.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    if (rawRules is! List) {
      return const OutputProcessingSettings();
    }
    final parsed = rawRules
        .whereType<Map>()
        .map((item) => OutputRegexRule.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return OutputProcessingSettings(rules: parsed);
  }

  @override
  List<Object?> get props => [rules];
}
