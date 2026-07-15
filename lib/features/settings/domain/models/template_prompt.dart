import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../../core/persistence/has_id_and_updated_at.dart';

/// 模板提示词中用于承载主输入框正文的保留变量名。
const templatePromptBodyVariableName = '正文';

/// 模板提示词变量的类型。
enum TemplatePromptVariableType {
  /// 纯文本变量（默认）。
  text,
  /// 数字变量，支持上下箭头微调。
  number;

  /// 从字符串解析变量类型，未知值回退为 [text]。
  static TemplatePromptVariableType fromString(String? raw) {
    return switch (raw?.toLowerCase()) {
      'number' => TemplatePromptVariableType.number,
      _ => TemplatePromptVariableType.text,
    };
  }

  @override
  String toString() => switch (this) {
        TemplatePromptVariableType.text => 'text',
        TemplatePromptVariableType.number => 'number',
      };
}

/// 模板提示词中的一个占位变量及其默认值。
class TemplatePromptVariable extends Equatable {
  const TemplatePromptVariable({
    required this.name,
    this.defaultValue = '',
    this.type = TemplatePromptVariableType.text,
  });

  final String name;
  final String defaultValue;
  final TemplatePromptVariableType type;

  /// 当前变量是否为主输入框对应的"正文"变量。
  bool get isBody => name == templatePromptBodyVariableName;

  /// 当前变量是否为数字类型。
  bool get isNumber => type == TemplatePromptVariableType.number;

  /// 复制变量并允许覆盖字段。
  TemplatePromptVariable copyWith({
    String? name,
    String? defaultValue,
    TemplatePromptVariableType? type,
  }) {
    return TemplatePromptVariable(
      name: name ?? this.name,
      defaultValue: defaultValue ?? this.defaultValue,
      type: type ?? this.type,
    );
  }

  /// 将变量序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'defaultValue': defaultValue,
      'type': type.toString(),
    };
  }

  /// 从 JSON 反序列化变量。
  factory TemplatePromptVariable.fromJson(Map<String, dynamic> json) {
    return TemplatePromptVariable(
      name: json['name'] as String,
      defaultValue: json['defaultValue'] as String? ?? '',
      type: TemplatePromptVariableType.fromString(
        json['type'] as String?,
      ),
    );
  }

  @override
  List<Object> get props => [name, defaultValue, type];
}

/// 可在聊天页临时注入变量的模板提示词。
class TemplatePrompt extends Equatable with HasIdAndUpdatedAt {
  const TemplatePrompt({
    required this.id,
    required this.title,
    required this.content,
    required this.variables,
    required this.updatedAt,
  });

  @override
  final String id;
  final String title;
  final String content;
  final List<TemplatePromptVariable> variables;
  @override
  final DateTime updatedAt;

  /// 模板中除"正文"外的变量列表。
  List<TemplatePromptVariable> get inputVariables {
    return variables.where((variable) => !variable.isBody).toList(growable: false);
  }

  /// 模板是否显式包含"正文"占位符。
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
