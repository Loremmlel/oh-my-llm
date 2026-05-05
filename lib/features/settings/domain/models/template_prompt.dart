import 'dart:convert';

import 'package:equatable/equatable.dart';

/// 模板提示词中用于承载主输入框正文的保留变量名。
const templatePromptBodyVariableName = '正文';

/// 模板提示词中的一个占位变量及其默认值。
class TemplatePromptVariable extends Equatable {
  const TemplatePromptVariable({
    required this.name,
    this.defaultValue = '',
  });

  final String name;
  final String defaultValue;

  /// 当前变量是否为主输入框对应的“正文”变量。
  bool get isBody => name == templatePromptBodyVariableName;

  /// 复制变量并允许覆盖字段。
  TemplatePromptVariable copyWith({
    String? name,
    String? defaultValue,
  }) {
    return TemplatePromptVariable(
      name: name ?? this.name,
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }

  /// 将变量序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'defaultValue': defaultValue,
    };
  }

  /// 从 JSON 反序列化变量。
  factory TemplatePromptVariable.fromJson(Map<String, dynamic> json) {
    return TemplatePromptVariable(
      name: json['name'] as String,
      defaultValue: json['defaultValue'] as String? ?? '',
    );
  }

  @override
  List<Object> get props => [name, defaultValue];
}

/// 可在聊天页临时注入变量的模板提示词。
class TemplatePrompt extends Equatable {
  const TemplatePrompt({
    required this.id,
    required this.title,
    required this.content,
    required this.variables,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final List<TemplatePromptVariable> variables;
  final DateTime updatedAt;

  /// 模板中除“正文”外的变量列表。
  List<TemplatePromptVariable> get inputVariables {
    return variables.where((variable) => !variable.isBody).toList(growable: false);
  }

  /// 模板是否显式包含“正文”占位符。
  bool get containsBodyVariable {
    return variables.any((variable) => variable.isBody);
  }

  /// 返回便于列表快速浏览的摘要。
  String get summary {
    final placeholderCount = variables.length;
    if (placeholderCount == 0) {
      return '无变量';
    }
    return '共 $placeholderCount 个变量';
  }

  /// 复制模板并允许覆盖字段。
  TemplatePrompt copyWith({
    String? id,
    String? title,
    String? content,
    List<TemplatePromptVariable>? variables,
    DateTime? updatedAt,
  }) {
    return TemplatePrompt(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      variables: variables ?? this.variables,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 将模板序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'variables': variables.map((variable) => variable.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化模板。
  factory TemplatePrompt.fromJson(Map<String, dynamic> json) {
    final rawVariables = json['variables'] as List<dynamic>? ?? const [];

    return TemplatePrompt(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      variables: rawVariables
          .map(
            (item) => TemplatePromptVariable.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, title, content, variables, updatedAt];
}
