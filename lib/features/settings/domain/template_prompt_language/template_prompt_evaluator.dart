import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';

/// 输出片段的分类：正文或模板片段，供消息气泡分段展示。
enum TemplatePromptOutputChunkKind { template, body }

/// 运行时变量值错误的类型。
enum TemplatePromptValueErrorCode { invalidNumber, invalidSelectValue }

/// 渲染结果中的一个输出片段。
final class TemplatePromptOutputChunk extends Equatable {
  const TemplatePromptOutputChunk({required this.text, required this.kind});

  final String text;
  final TemplatePromptOutputChunkKind kind;

  @override
  List<Object> get props => [text, kind];
}

/// 运行时变量值错误，附着到对应字段并阻止发送。
final class TemplatePromptValueError extends Equatable {
  const TemplatePromptValueError({
    required this.variableName,
    required this.code,
    required this.message,
  });

  final String variableName;
  final TemplatePromptValueErrorCode code;
  final String message;

  @override
  List<Object> get props => [variableName, code, message];
}

/// 一次求值的完整结果：输出片段、活跃变量、有效值快照与值错误。
final class TemplatePromptEvaluation extends Equatable {
  TemplatePromptEvaluation({
    required List<TemplatePromptOutputChunk> chunks,
    required List<String> activeInputVariableNames,
    required Map<String, String> effectiveValues,
    required List<TemplatePromptValueError> valueErrors,
  }) : chunks = List.unmodifiable(chunks),
       activeInputVariableNames = List.unmodifiable(activeInputVariableNames),
       effectiveValues = Map.unmodifiable(effectiveValues),
       valueErrors = List.unmodifiable(valueErrors);

  final List<TemplatePromptOutputChunk> chunks;
  final List<String> activeInputVariableNames;
  final Map<String, String> effectiveValues;
  final List<TemplatePromptValueError> valueErrors;

  bool get isValid => valueErrors.isEmpty;

  String get content => chunks.map((chunk) => chunk.text).join();

  @override
  List<Object> get props => [
    chunks,
    activeInputVariableNames,
    effectiveValues,
    valueErrors,
  ];
}

/// 归一化聊天草稿中的变量值：空输入回落配置默认值；单选候选不在
/// 选项列表时回落配置默认值（编译器保证该默认值有效）。
///
/// 只处理字段绑定阶段的合法性回落，不校验数字；发送边界由
/// [evaluateTemplatePrompt] 更严格地拒绝非法值。
String normalizeTemplatePromptVariableDraftValue(
  TemplatePromptVariable variable,
  String? rawValue,
) {
  final trimmed = rawValue?.trim() ?? '';
  final candidate = trimmed.isEmpty ? variable.defaultValue : trimmed;
  if (variable.isSelect && !variable.options.contains(candidate)) {
    return variable.defaultValue;
  }
  return candidate;
}

/// 求值已编译模板：解析有效值、选择分支、渲染片段并投影活跃变量。
///
/// 求值比字段绑定更严格：空输入使用配置默认值，但非空 select 值不在
/// 选项列表或数字非法时不回落猜测，而是返回类型化值错误，由发送边界
/// 拒绝。控制值无效时不选分支，但仍暴露控制与顶层字段供用户修复。
TemplatePromptEvaluation evaluateTemplatePrompt({
  required TemplatePromptProgram program,
  required String body,
  required Map<String, String> variableValues,
}) {
  final normalizedBody = body.trim();
  final effectiveValues = <String, String>{};
  final valueErrors = <TemplatePromptValueError>[];
  final invalidControlNames = <String>{};

  // 为每个声明变量解析有效值：空输入回落默认值，非空输入去除两端空白；
  // 非法数字与 select 值记录错误，且当该变量参与条件时标记为不可判。
  for (final variable in program.inputVariables) {
    final trimmed = (variableValues[variable.name] ?? '').trim();
    final candidate = trimmed.isEmpty ? variable.defaultValue : trimmed;
    effectiveValues[variable.name] = candidate;
    if (trimmed.isEmpty) {
      continue;
    }
    switch (variable.type) {
      case TemplatePromptVariableType.number:
        if (int.tryParse(candidate) == null) {
          valueErrors.add(
            TemplatePromptValueError(
              variableName: variable.name,
              code: TemplatePromptValueErrorCode.invalidNumber,
              message: '「${variable.name}」必须是整数',
            ),
          );
          if (program.conditionVariableNames.contains(variable.name)) {
            invalidControlNames.add(variable.name);
          }
        }
      case TemplatePromptVariableType.select:
        if (!variable.options.contains(candidate)) {
          valueErrors.add(
            TemplatePromptValueError(
              variableName: variable.name,
              code: TemplatePromptValueErrorCode.invalidSelectValue,
              message: '「${variable.name}」必须是选项之一',
            ),
          );
          if (program.conditionVariableNames.contains(variable.name)) {
            invalidControlNames.add(variable.name);
          }
        }
      case TemplatePromptVariableType.text:
        break;
    }
  }

  final chunks = <TemplatePromptOutputChunk>[];
  final topLevelVariableNames = <String>{};
  final branchVariableNames = <String>{};

  void addChunk(String text, TemplatePromptOutputChunkKind kind) {
    if (text.isEmpty) {
      return;
    }
    if (chunks.isNotEmpty && chunks.last.kind == kind) {
      final previous = chunks.removeLast();
      chunks.add(
        TemplatePromptOutputChunk(text: '${previous.text}$text', kind: kind),
      );
      return;
    }
    chunks.add(TemplatePromptOutputChunk(text: text, kind: kind));
  }

  // 从上到下选择首个成立分支；控制值无效时不猜分支，整块跳过。
  List<TemplatePromptNode>? selectBranch(TemplatePromptIfNode node) {
    for (final branch in node.branches) {
      if (invalidControlNames.contains(branch.condition.variableName)) {
        return null;
      }
      if (_evaluateCondition(branch.condition, effectiveValues)) {
        return branch.nodes;
      }
    }
    return node.elseNodes;
  }

  void walk(List<TemplatePromptNode> nodes, {required bool inBranch}) {
    for (final node in nodes) {
      switch (node) {
        case TemplatePromptTextNode(:final text):
          addChunk(text, TemplatePromptOutputChunkKind.template);
        case TemplatePromptVariableNode(:final name):
          if (inBranch) {
            branchVariableNames.add(name);
          } else {
            topLevelVariableNames.add(name);
          }
          if (name == templatePromptBodyVariableName) {
            addChunk(normalizedBody, TemplatePromptOutputChunkKind.body);
          } else {
            addChunk(
              effectiveValues[name] ?? '',
              TemplatePromptOutputChunkKind.template,
            );
          }
        case TemplatePromptIfNode():
          final selected = selectBranch(node);
          if (selected != null) {
            walk(selected, inBranch: true);
          }
      }
    }
  }

  walk(program.nodes, inBranch: false);

  // 无顶层正文变量时保持现有前置行为：非空正文在前，仅当模板渲染内容
  // 非空时再补一个换行；正文与模板始终是两种不同 kind 的片段。
  if (!program.containsBodyVariable && normalizedBody.isNotEmpty) {
    final renderedContent = chunks.map((chunk) => chunk.text).join();
    final prefix = renderedContent.isEmpty
        ? normalizedBody
        : '$normalizedBody\n';
    chunks.insert(
      0,
      TemplatePromptOutputChunk(
        text: prefix,
        kind: TemplatePromptOutputChunkKind.body,
      ),
    );
  }

  // 活跃变量按声明出现顺序投影：条件控制变量、顶层输入变量与选中分支
  // 内的变量；分支未选中或控制值无效时，其变量不进入活跃列表。
  final activeInputVariableNames = <String>[
    for (final variable in program.inputVariables)
      if (program.conditionVariableNames.contains(variable.name) ||
          topLevelVariableNames.contains(variable.name) ||
          branchVariableNames.contains(variable.name))
        variable.name,
  ];

  return TemplatePromptEvaluation(
    chunks: chunks,
    activeInputVariableNames: activeInputVariableNames,
    effectiveValues: effectiveValues,
    valueErrors: valueErrors,
  );
}

bool _evaluateCondition(
  TemplatePromptCondition condition,
  Map<String, String> effectiveValues,
) {
  final effectiveValue = effectiveValues[condition.variableName] ?? '';
  switch (condition.literal) {
    case TemplatePromptStringLiteral(:final value):
      return switch (condition.operator) {
        TemplatePromptComparisonOperator.equal => effectiveValue == value,
        TemplatePromptComparisonOperator.notEqual => effectiveValue != value,
        _ => false,
      };
    case TemplatePromptIntegerLiteral(:final value):
      // 控制值非法时调用方已跳过该分支，此处仅防御意外路径。
      final parsed = int.tryParse(effectiveValue);
      if (parsed == null) {
        return false;
      }
      return switch (condition.operator) {
        TemplatePromptComparisonOperator.equal => parsed == value,
        TemplatePromptComparisonOperator.notEqual => parsed != value,
        TemplatePromptComparisonOperator.greater => parsed > value,
        TemplatePromptComparisonOperator.greaterOrEqual => parsed >= value,
        TemplatePromptComparisonOperator.less => parsed < value,
        TemplatePromptComparisonOperator.lessOrEqual => parsed <= value,
      };
  }
}
