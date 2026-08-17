import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

/// 模板提示词编译错误的稳定错误码。
enum TemplatePromptErrorCode {
  /// 占位符语法无效（空占位符、变量名缺失、数字变量携带选项等）。
  invalidPlaceholder,

  /// 单选变量的选项不足两个、去除两端空白后为空或重复。
  invalidSelectOptions,

  /// 同名变量的多次类型声明在类型或选项上不一致。
  conflictingVariableDeclaration,

  /// {{正文}} 携带了类型标记。
  invalidBodyDeclaration,

  /// {{正文}} 出现在条件分支内部。
  bodyInsideConditional,

  /// 条件表达式语法无效（缺少运算符、多余内容等）。
  invalidConditionSyntax,

  /// 条件引用了未声明的变量。
  undefinedConditionVariable,

  /// 变量类型不支持条件中使用的比较运算符。
  invalidConditionOperator,

  /// 条件字面量不合法（类型不符、非法转义或不是已声明选项）。
  invalidConditionLiteral,

  /// 控制标签出现在不应出现的位置、无法识别或未闭合。
  unexpectedControlTag,

  /// {{else}} 之后继续出现 {{else if}}。
  elseIfAfterElse,

  /// 条件块出现多个 {{else}}。
  duplicateElse,

  /// 条件块缺少对应的 {{/if}}。
  unclosedIf,

  /// 条件块内部嵌套了新的条件块。
  nestedIf,

  /// 已保存的变量定义与模板正文声明不一致。
  inconsistentStoredVariables,
}

/// 源码位置，行号与列号均为 1 起。
final class TemplatePromptSourceLocation extends Equatable {
  const TemplatePromptSourceLocation({
    required this.offset,
    required this.line,
    required this.column,
  });

  final int offset;
  final int line;
  final int column;

  @override
  List<Object> get props => [offset, line, column];
}

/// 一条带稳定错误码与源码位置的编译诊断。
final class TemplatePromptDiagnostic extends Equatable {
  const TemplatePromptDiagnostic({
    required this.code,
    required this.location,
    required this.message,
  });

  final TemplatePromptErrorCode code;
  final TemplatePromptSourceLocation location;
  final String message;

  @override
  List<Object> get props => [code, location, message];
}

/// 条件表达式支持的比较运算符。
enum TemplatePromptComparisonOperator {
  equal,
  notEqual,
  greater,
  greaterOrEqual,
  less,
  lessOrEqual,
}

/// 条件表达式右值的类型化字面量。
sealed class TemplatePromptConditionLiteral extends Equatable {
  const TemplatePromptConditionLiteral();
}

/// 双引号字符串字面量，保留内部空白。
final class TemplatePromptStringLiteral extends TemplatePromptConditionLiteral {
  const TemplatePromptStringLiteral(this.value);

  final String value;

  @override
  List<Object> get props => [value];
}

/// 十进制整数字面量。
final class TemplatePromptIntegerLiteral
    extends TemplatePromptConditionLiteral {
  const TemplatePromptIntegerLiteral(this.value);

  final int value;

  @override
  List<Object> get props => [value];
}

/// 已解析的条件表达式，字面量在编译期定型，求值不再重解析。
final class TemplatePromptCondition extends Equatable {
  const TemplatePromptCondition({
    required this.variableName,
    required this.operator,
    required this.literal,
  });

  final String variableName;
  final TemplatePromptComparisonOperator operator;
  final TemplatePromptConditionLiteral literal;

  @override
  List<Object> get props => [variableName, operator, literal];
}

/// 模板程序 AST 节点。
sealed class TemplatePromptNode extends Equatable {
  const TemplatePromptNode();
}

/// 普通文本节点。
final class TemplatePromptTextNode extends TemplatePromptNode {
  const TemplatePromptTextNode(this.text);

  final String text;

  @override
  List<Object> get props => [text];
}

/// 变量插值节点。
final class TemplatePromptVariableNode extends TemplatePromptNode {
  const TemplatePromptVariableNode(this.name);

  final String name;

  @override
  List<Object> get props => [name];
}

/// 条件块的一个分支：条件及其节点。
final class TemplatePromptConditionalBranch extends Equatable {
  TemplatePromptConditionalBranch({
    required this.condition,
    required List<TemplatePromptNode> nodes,
  }) : nodes = List.unmodifiable(nodes);

  final TemplatePromptCondition condition;
  final List<TemplatePromptNode> nodes;

  @override
  List<Object> get props => [condition, nodes];
}

/// 条件块节点，由有序分支与可选的 else 节点组成。
final class TemplatePromptIfNode extends TemplatePromptNode {
  TemplatePromptIfNode({
    required List<TemplatePromptConditionalBranch> branches,
    List<TemplatePromptNode>? elseNodes,
  }) : branches = List.unmodifiable(branches),
       elseNodes = elseNodes == null ? null : List.unmodifiable(elseNodes);

  final List<TemplatePromptConditionalBranch> branches;
  final List<TemplatePromptNode>? elseNodes;

  @override
  List<Object?> get props => [branches, elseNodes];
}

/// 编译完成的不可变模板程序。
final class TemplatePromptProgram extends Equatable {
  TemplatePromptProgram({
    required List<TemplatePromptNode> nodes,
    required List<TemplatePromptVariable> declarations,
    required Set<String> conditionVariableNames,
    required this.containsBodyVariable,
  }) : nodes = List.unmodifiable(nodes),
       declarations = List.unmodifiable(declarations),
       conditionVariableNames = Set.unmodifiable(conditionVariableNames);

  final List<TemplatePromptNode> nodes;
  final List<TemplatePromptVariable> declarations;
  final Set<String> conditionVariableNames;
  final bool containsBodyVariable;

  /// 除"正文"外的输入变量。
  List<TemplatePromptVariable> get inputVariables =>
      List.unmodifiable(declarations.where((variable) => !variable.isBody));

  @override
  List<Object> get props => [
    nodes,
    declarations,
    conditionVariableNames,
    containsBodyVariable,
  ];
}

/// 编译结果：有效程序与全部诊断。
final class TemplatePromptCompilation extends Equatable {
  TemplatePromptCompilation({
    this.program,
    List<TemplatePromptDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  final TemplatePromptProgram? program;
  final List<TemplatePromptDiagnostic> diagnostics;

  bool get isValid => program != null && diagnostics.isEmpty;

  @override
  List<Object?> get props => [program, diagnostics];
}
