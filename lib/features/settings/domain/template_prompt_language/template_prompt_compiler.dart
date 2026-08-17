import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';

final _integerPattern = RegExp(r'^-?[0-9]+$');

/// 编译模板正文，生成不可变程序与诊断。
///
/// 扫描与校验分两趟进行：先按源码顺序扫描标签并构建兄弟级条件块，
/// 再统一解析变量声明并校验条件，因此条件可以引用其后才声明的变量。
TemplatePromptCompilation compileTemplatePromptContent(String content) {
  final diagnostics = <TemplatePromptDiagnostic>[];
  final items = _scanItems(content, diagnostics);

  final nodes = <TemplatePromptNode>[];
  final occurrences = <_VariableOccurrence>[];
  final conditions = <_Condition>[];
  _IfBlock? openBlock;

  var i = 0;
  while (i < items.length) {
    final item = items[i];
    if (item is _TextItem) {
      final text = content.substring(item.start, item.end);
      if (openBlock == null) {
        nodes.add(TemplatePromptTextNode(text));
      } else if (openBlock.sawElse) {
        openBlock.elseNodes!.add(TemplatePromptTextNode(text));
      } else {
        openBlock.branches.last.nodes.add(TemplatePromptTextNode(text));
      }
      i++;
      continue;
    }

    final tag = item as _TagItem;
    switch (tag.kind) {
      case _TagKind.variable:
        final parsed = _parseVariableTag(
          tag.content.trim(),
          tag.start,
          content,
          diagnostics,
        );
        if (parsed == null) {
          i++;
          continue;
        }
        final node = TemplatePromptVariableNode(parsed.name);
        if (parsed.isBody) {
          if (parsed.type != TemplatePromptVariableType.text) {
            diagnostics.add(
              _diag(
                TemplatePromptErrorCode.invalidBodyDeclaration,
                _loc(content, tag.start),
                '{{正文}} 不允许携带类型标记',
              ),
            );
          }
          if (openBlock != null) {
            diagnostics.add(
              _diag(
                TemplatePromptErrorCode.bodyInsideConditional,
                _loc(content, tag.start),
                '{{正文}} 只能出现在条件块之外',
              ),
            );
          }
          if (openBlock == null &&
              parsed.type == TemplatePromptVariableType.text) {
            occurrences.add(
              _VariableOccurrence(
                name: parsed.name,
                type: null,
                options: null,
                offset: tag.start,
              ),
            );
            nodes.add(node);
          }
        } else {
          occurrences.add(
            _VariableOccurrence(
              name: parsed.name,
              type: parsed.hasType ? parsed.type : null,
              options:
                  parsed.hasType &&
                      parsed.type == TemplatePromptVariableType.select
                  ? parsed.options
                  : null,
              offset: tag.start,
            ),
          );
          if (openBlock == null) {
            nodes.add(node);
          } else if (openBlock.sawElse) {
            openBlock.elseNodes!.add(node);
          } else {
            openBlock.branches.last.nodes.add(node);
          }
        }
        i++;
        continue;
      case _TagKind.ifOpen:
        if (openBlock != null) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.nestedIf,
              _loc(content, tag.start),
              '条件块内不允许嵌套 {{#if}}',
            ),
          );
          // 跳过整个内层条件块，避免其内部标签干扰外层结构。
          i = _findMatchingClose(items, i) + 1;
        } else {
          openBlock = _IfBlock(openOffset: tag.start);
          openBlock.branches.add(
            _BranchBuilder(
              condition: _parseCondition(
                tag.conditionRaw!,
                tag.start,
                content,
                diagnostics,
                conditions,
              ),
            ),
          );
          i++;
        }
        continue;
      case _TagKind.elseIf:
        if (openBlock == null) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.unexpectedControlTag,
              _loc(content, tag.start),
              '{{else if}} 缺少对应的 {{#if}}',
            ),
          );
        } else if (openBlock.sawElse) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.elseIfAfterElse,
              _loc(content, tag.start),
              '{{else}} 之后不能再出现 {{else if}}',
            ),
          );
        } else {
          openBlock.branches.add(
            _BranchBuilder(
              condition: _parseCondition(
                tag.conditionRaw!,
                tag.start,
                content,
                diagnostics,
                conditions,
              ),
            ),
          );
        }
        i++;
        continue;
      case _TagKind.elseTag:
        if (openBlock == null) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.unexpectedControlTag,
              _loc(content, tag.start),
              '{{else}} 缺少对应的 {{#if}}',
            ),
          );
        } else if (openBlock.sawElse) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.duplicateElse,
              _loc(content, tag.start),
              '条件块只能有一个 {{else}}',
            ),
          );
        } else {
          openBlock.sawElse = true;
          openBlock.elseNodes = <TemplatePromptNode>[];
        }
        i++;
        continue;
      case _TagKind.closeIf:
        if (openBlock == null) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.unexpectedControlTag,
              _loc(content, tag.start),
              '{{/if}} 缺少对应的 {{#if}}',
            ),
          );
        } else {
          nodes.add(
            TemplatePromptIfNode(
              branches: [
                for (final branch in openBlock.branches)
                  TemplatePromptConditionalBranch(
                    condition: branch.condition,
                    nodes: branch.nodes,
                  ),
              ],
              elseNodes: openBlock.sawElse ? openBlock.elseNodes : null,
            ),
          );
          openBlock = null;
        }
        i++;
        continue;
      case _TagKind.unexpectedControl:
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.unexpectedControlTag,
            _loc(content, tag.start),
            '无法识别的控制标签 {{${tag.content.trim()}}}',
          ),
        );
        i++;
        continue;
    }
  }

  if (openBlock != null) {
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.unclosedIf,
        _loc(content, openBlock.openOffset),
        '缺少与 {{#if}} 对应的 {{/if}}',
      ),
    );
  }

  final declarations = _resolveDeclarations(occurrences, content, diagnostics);
  final declarationsByName = <String, TemplatePromptVariable>{
    for (final declaration in declarations) declaration.name: declaration,
  };
  for (final condition in conditions) {
    _validateCondition(condition, declarationsByName, content, diagnostics);
  }

  if (diagnostics.isNotEmpty) {
    return TemplatePromptCompilation(program: null, diagnostics: diagnostics);
  }

  return TemplatePromptCompilation(
    program: TemplatePromptProgram(
      nodes: nodes,
      declarations: declarations,
      conditionVariableNames: {
        for (final condition in conditions)
          if (condition.variable != null) condition.variable!,
      },
      containsBodyVariable: declarations.any((variable) => variable.isBody),
    ),
  );
}

/// 编译模板定义：内容编译失败时透传内容诊断，否则校验已保存变量与
/// 正文声明的形状一致性，并让程序声明携带校验后的持久化默认值。
TemplatePromptCompilation compileTemplatePromptDefinition(
  TemplatePrompt templatePrompt,
) {
  final contentResult = compileTemplatePromptContent(templatePrompt.content);
  final program = contentResult.program;
  if (program == null) {
    return contentResult;
  }

  final persisted = templatePrompt.variables;
  final compiled = program.declarations;
  if (persisted.length != compiled.length) {
    return _inconsistentStoredVariables('已保存的变量数量与模板正文声明不一致');
  }
  for (var i = 0; i < compiled.length; i++) {
    final declaration = compiled[i];
    final saved = persisted[i];
    if (saved.name != declaration.name) {
      return _inconsistentStoredVariables(
        '已保存的变量「${saved.name}」与模板正文声明的「${declaration.name}」不一致',
      );
    }
    if (saved.type != declaration.type) {
      return _inconsistentStoredVariables('已保存的变量「${saved.name}」类型与模板正文声明不一致');
    }
    if (saved.type == TemplatePromptVariableType.select &&
        !_stringListEquals(saved.options, declaration.options)) {
      return _inconsistentStoredVariables('已保存的变量「${saved.name}」选项与模板正文声明不一致');
    }
    switch (declaration.type) {
      case TemplatePromptVariableType.number:
        if (int.tryParse(saved.defaultValue) == null) {
          return _inconsistentStoredVariables('数字变量「${saved.name}」的默认值不是合法整数');
        }
      case TemplatePromptVariableType.select:
        if (!declaration.options.contains(saved.defaultValue)) {
          return _inconsistentStoredVariables('单选变量「${saved.name}」的默认值不在选项列表中');
        }
      case TemplatePromptVariableType.text:
        break;
    }
  }

  return TemplatePromptCompilation(
    program: TemplatePromptProgram(
      nodes: program.nodes,
      declarations: [
        for (var i = 0; i < compiled.length; i++)
          TemplatePromptVariable(
            name: compiled[i].name,
            defaultValue: compiled[i].isBody ? '' : persisted[i].defaultValue,
            type: compiled[i].type,
            options: compiled[i].options,
          ),
      ],
      conditionVariableNames: program.conditionVariableNames,
      containsBodyVariable: program.containsBodyVariable,
    ),
  );
}

/// 依据程序声明协调变量列表：保留有效默认值，新建数字默认 1，
/// 新建单选默认首个选项，单选配置默认值失效时回落到首个选项。
List<TemplatePromptVariable> reconcileCompiledTemplatePromptVariables({
  required TemplatePromptProgram program,
  required List<TemplatePromptVariable> existingVariables,
}) {
  final existingByName = <String, TemplatePromptVariable>{
    for (final variable in existingVariables) variable.name: variable,
  };
  return [
    for (final declaration in program.declarations)
      () {
        if (declaration.isBody) {
          return const TemplatePromptVariable(
            name: templatePromptBodyVariableName,
          );
        }
        final existing = existingByName[declaration.name];
        final defaultValue = switch (declaration.type) {
          TemplatePromptVariableType.number => existing?.defaultValue ?? '1',
          TemplatePromptVariableType.select =>
            existing != null &&
                    declaration.options.contains(existing.defaultValue)
                ? existing.defaultValue
                : declaration.options.first,
          TemplatePromptVariableType.text => existing?.defaultValue ?? '',
        };
        return TemplatePromptVariable(
          name: declaration.name,
          defaultValue: defaultValue,
          type: declaration.type,
          options: declaration.options,
        );
      }(),
  ];
}

// ── 扫描 ────────────────────────────────────────────────────

sealed class _Item {
  const _Item();
}

class _TextItem extends _Item {
  const _TextItem(this.start, this.end);

  final int start;
  final int end;
}

class _TagItem extends _Item {
  const _TagItem({
    required this.start,
    required this.end,
    required this.effectiveStart,
    required this.effectiveEnd,
    required this.content,
    required this.kind,
    this.conditionRaw,
  });

  final int start;
  final int end;
  final int effectiveStart;
  final int effectiveEnd;
  final String content;
  final _TagKind kind;
  final String? conditionRaw;
}

enum _TagKind { variable, ifOpen, elseIf, elseTag, closeIf, unexpectedControl }

/// 按源码顺序扫描文本与完整 `{{...}}` 标签。
///
/// 控制标签独占一行时，有效区间扩展为整行（含前导空白与行结束符），
/// 从而把该行从渲染文本中整体裁剪；变量标签永远只移除标签本身。
List<_Item> _scanItems(
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
) {
  final items = <_Item>[];
  var cursor = 0;
  var i = 0;
  while (i < content.length) {
    if (!content.startsWith('{{', i)) {
      i++;
      continue;
    }
    final close = content.indexOf('}}', i + 2);
    if (close == -1) {
      // 未闭合的标签：仅当看起来是控制标签时才报错，其余保持文本行为。
      if (_isIncompleteControlTag(content.substring(i + 2))) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.unexpectedControlTag,
            _loc(content, i),
            '控制标签未闭合，缺少 }}',
          ),
        );
      }
      i += 2;
      continue;
    }
    final inner = content.substring(i + 2, close);
    if (inner.contains('{') || inner.contains('}')) {
      // 内部含花括号的片段与旧解析器一致，作为普通文本留在原地。
      i += 2;
      continue;
    }
    final tagEnd = close + 2;
    final classification = _classifyTag(inner.trim());
    var effectiveStart = i;
    var effectiveEnd = tagEnd;
    if (classification.kind != _TagKind.variable) {
      final lineStart = (i > 0 ? content.lastIndexOf('\n', i - 1) : -1) + 1;
      final newline = content.indexOf('\n', tagEnd);
      final lineEnd = newline == -1 ? content.length : newline;
      final leading = content.substring(lineStart, i);
      final trailing = content.substring(tagEnd, lineEnd);
      if (leading.trim().isEmpty && trailing.trim().isEmpty) {
        effectiveStart = lineStart;
        effectiveEnd = newline == -1 ? content.length : newline + 1;
      }
    }
    if (effectiveStart > cursor) {
      items.add(_TextItem(cursor, effectiveStart));
    }
    items.add(
      _TagItem(
        start: i,
        end: tagEnd,
        effectiveStart: effectiveStart,
        effectiveEnd: effectiveEnd,
        content: inner,
        kind: classification.kind,
        conditionRaw: classification.condition,
      ),
    );
    cursor = effectiveEnd;
    i = tagEnd;
  }
  if (cursor < content.length) {
    items.add(_TextItem(cursor, content.length));
  }
  return items;
}

({_TagKind kind, String? condition}) _classifyTag(String trimmed) {
  if (trimmed == 'else') {
    return (kind: _TagKind.elseTag, condition: null);
  }
  if (trimmed.startsWith('else ')) {
    final rest = trimmed.substring(5).trim();
    if (rest.startsWith('if') &&
        (rest.length == 2 || _isWhitespaceCodeUnit(rest.codeUnitAt(2)))) {
      return (kind: _TagKind.elseIf, condition: rest.substring(2).trim());
    }
    return (kind: _TagKind.unexpectedControl, condition: null);
  }
  if (trimmed.startsWith('#if') &&
      (trimmed.length == 3 || _isWhitespaceCodeUnit(trimmed.codeUnitAt(3)))) {
    return (kind: _TagKind.ifOpen, condition: trimmed.substring(3).trim());
  }
  if (trimmed.startsWith('/if') &&
      (trimmed.length == 3 || _isWhitespaceCodeUnit(trimmed.codeUnitAt(3)))) {
    if (trimmed.length > 3) {
      return (kind: _TagKind.unexpectedControl, condition: null);
    }
    return (kind: _TagKind.closeIf, condition: null);
  }
  if (trimmed.startsWith('#') || trimmed.startsWith('/')) {
    return (kind: _TagKind.unexpectedControl, condition: null);
  }
  return (kind: _TagKind.variable, condition: null);
}

bool _isIncompleteControlTag(String tail) {
  if (tail.startsWith('#') || tail.startsWith('/')) {
    return true;
  }
  return tail.startsWith('else') &&
      (tail.length == 4 || _isWhitespaceCodeUnit(tail.codeUnitAt(4)));
}

/// 找到与 [nestedIfIndex] 处内层 {{#if}} 配对的 {{/if}}，用于跳过整个内层块。
int _findMatchingClose(List<_Item> items, int nestedIfIndex) {
  var depth = 1;
  for (var j = nestedIfIndex + 1; j < items.length; j++) {
    final item = items[j];
    if (item is! _TagItem) {
      continue;
    }
    final trimmed = item.content.trim();
    if (trimmed.startsWith('#if') &&
        (trimmed.length == 3 || _isWhitespaceCodeUnit(trimmed.codeUnitAt(3)))) {
      depth++;
    } else if (trimmed.startsWith('/if') &&
        (trimmed.length == 3 || _isWhitespaceCodeUnit(trimmed.codeUnitAt(3)))) {
      depth--;
      if (depth == 0) {
        return j;
      }
    }
  }
  return items.length;
}

// ── 变量声明 ────────────────────────────────────────────────

class _ParsedVariable {
  const _ParsedVariable({
    required this.name,
    required this.type,
    required this.hasType,
    required this.options,
  });

  final String name;
  final TemplatePromptVariableType type;

  /// 是否携带可识别的类型标记（number / select）。
  ///
  /// 未知类型标记回退为文本但不算类型声明，因此后续出现真正的类型声明时
  /// 仍可统一解析，不会被这次回退提前锁定。
  final bool hasType;
  final List<String> options;

  bool get isBody => name == templatePromptBodyVariableName;
}

class _VariableOccurrence {
  const _VariableOccurrence({
    required this.name,
    this.type,
    this.options,
    required this.offset,
  });

  final String name;
  final TemplatePromptVariableType? type;
  final List<String>? options;
  final int offset;
}

_ParsedVariable? _parseVariableTag(
  String trimmed,
  int offset,
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
) {
  final colon = trimmed.indexOf(':');
  if (colon == -1) {
    if (trimmed.isEmpty) {
      diagnostics.add(
        _diag(
          TemplatePromptErrorCode.invalidPlaceholder,
          _loc(content, offset),
          '占位符内容为空',
        ),
      );
      return null;
    }
    if (trimmed.contains('|')) {
      diagnostics.add(
        _diag(
          TemplatePromptErrorCode.invalidPlaceholder,
          _loc(content, offset),
          '非 select 变量的占位符不能包含 |',
        ),
      );
      return null;
    }
    return _ParsedVariable(
      name: trimmed,
      type: TemplatePromptVariableType.text,
      hasType: false,
      options: const [],
    );
  }
  final name = trimmed.substring(0, colon).trim();
  if (name.isEmpty) {
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.invalidPlaceholder,
        _loc(content, offset),
        '变量名不能为空',
      ),
    );
    return null;
  }
  final segments = trimmed.substring(colon + 1).split('|');
  final typeToken = segments.first.trim();
  final options = segments
      .skip(1)
      .map((segment) => segment.trim())
      .toList(growable: false);
  switch (typeToken) {
    case 'number':
      if (options.isNotEmpty) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidPlaceholder,
            _loc(content, offset),
            '数字变量不允许携带选项',
          ),
        );
        return null;
      }
      return _ParsedVariable(
        name: name,
        type: TemplatePromptVariableType.number,
        hasType: true,
        options: const [],
      );
    case 'select':
      if (options.length < 2) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidSelectOptions,
            _loc(content, offset),
            '单选变量至少需要两个选项',
          ),
        );
        return null;
      }
      if (options.any((option) => option.isEmpty)) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidSelectOptions,
            _loc(content, offset),
            '单选选项不能为空',
          ),
        );
        return null;
      }
      if (options.toSet().length != options.length) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidSelectOptions,
            _loc(content, offset),
            '单选选项不能重复',
          ),
        );
        return null;
      }
      return _ParsedVariable(
        name: name,
        type: TemplatePromptVariableType.select,
        hasType: true,
        options: List.unmodifiable(options),
      );
    default:
      // 未知类型回退为文本，与旧解析器一致，选项一并忽略。
      return _ParsedVariable(
        name: name,
        type: TemplatePromptVariableType.text,
        hasType: false,
        options: const [],
      );
  }
}

List<TemplatePromptVariable> _resolveDeclarations(
  List<_VariableOccurrence> occurrences,
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
) {
  final namesInOrder = <String>[];
  final typedByName = <String, _VariableOccurrence>{};
  for (final occurrence in occurrences) {
    if (!namesInOrder.contains(occurrence.name)) {
      namesInOrder.add(occurrence.name);
    }
    final type = occurrence.type;
    if (type == null) {
      continue;
    }
    final existing = typedByName[occurrence.name];
    if (existing == null) {
      typedByName[occurrence.name] = occurrence;
      continue;
    }
    final conflict =
        existing.type != type ||
        (type == TemplatePromptVariableType.select &&
            !_stringListEquals(existing.options!, occurrence.options!));
    if (conflict) {
      diagnostics.add(
        _diag(
          TemplatePromptErrorCode.conflictingVariableDeclaration,
          _loc(content, occurrence.offset),
          '变量「${occurrence.name}」的多次类型声明不一致',
        ),
      );
    }
  }
  return [
    for (final name in namesInOrder)
      () {
        final typed = typedByName[name];
        if (typed == null) {
          return TemplatePromptVariable(name: name);
        }
        return TemplatePromptVariable(
          name: name,
          defaultValue: switch (typed.type!) {
            TemplatePromptVariableType.number => '1',
            TemplatePromptVariableType.select => typed.options!.first,
            TemplatePromptVariableType.text => '',
          },
          type: typed.type!,
          options: typed.options ?? const [],
        );
      }(),
  ];
}

// ── 条件解析与校验 ──────────────────────────────────────────

class _Condition {
  const _Condition({
    required this.variable,
    required this.operator,
    required this.literal,
    required this.offset,
  });

  final String? variable;
  final String? operator;
  final Object? literal;
  final int offset;
}

/// 解析条件并返回分支使用的条件对象；语法错误时返回占位条件并记录诊断，
/// 占位条件只会出现在被判定为无效、随后丢弃的程序中。
TemplatePromptCondition _parseCondition(
  String raw,
  int offset,
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
  List<_Condition> conditions,
) {
  final trimmed = raw.trim();
  var end = 0;
  while (end < trimmed.length &&
      !_isWhitespaceCodeUnit(trimmed.codeUnitAt(end))) {
    end++;
  }
  final name = trimmed.substring(0, end);
  final rest = trimmed.substring(end).trimLeft();
  String? operator;
  for (final candidate in const ['>=', '<=', '==', '!=', '>', '<']) {
    if (rest.startsWith(candidate)) {
      operator = candidate;
      break;
    }
  }
  if (name.isEmpty || operator == null) {
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.invalidConditionSyntax,
        _loc(content, offset),
        '条件表达式格式错误，应为「变量 运算符 字面量」',
      ),
    );
    conditions.add(
      _Condition(variable: null, operator: null, literal: null, offset: offset),
    );
    return _placeholderCondition();
  }
  final literal = _parseConditionLiteral(
    rest.substring(operator.length).trim(),
    offset,
    content,
    diagnostics,
  );
  if (literal == null) {
    conditions.add(
      _Condition(variable: null, operator: null, literal: null, offset: offset),
    );
    return _placeholderCondition();
  }
  conditions.add(
    _Condition(
      variable: name,
      operator: operator,
      literal: literal,
      offset: offset,
    ),
  );
  return TemplatePromptCondition(
    variableName: name,
    operator: _operatorFromString(operator)!,
    literal: literal is int
        ? TemplatePromptIntegerLiteral(literal)
        : TemplatePromptStringLiteral(literal as String),
  );
}

TemplatePromptCondition _placeholderCondition() =>
    const TemplatePromptCondition(
      variableName: '',
      operator: TemplatePromptComparisonOperator.equal,
      literal: TemplatePromptStringLiteral(''),
    );

Object? _parseConditionLiteral(
  String raw,
  int offset,
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
) {
  if (raw.startsWith('"')) {
    final buffer = StringBuffer();
    var i = 1;
    while (i < raw.length) {
      final char = raw[i];
      if (char == '\\') {
        if (i + 1 >= raw.length) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.invalidConditionLiteral,
              _loc(content, offset),
              '字符串字面量以未转义的反斜杠结尾',
            ),
          );
          return null;
        }
        final next = raw[i + 1];
        if (next == '"') {
          buffer.write('"');
          i += 2;
        } else if (next == '\\') {
          buffer.write('\\');
          i += 2;
        } else {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.invalidConditionLiteral,
              _loc(content, offset),
              '字符串字面量不支持转义 \\$next',
            ),
          );
          return null;
        }
      } else if (char == '"') {
        if (i != raw.length - 1) {
          diagnostics.add(
            _diag(
              TemplatePromptErrorCode.invalidConditionSyntax,
              _loc(content, offset),
              '字符串字面量后存在多余内容',
            ),
          );
          return null;
        }
        return buffer.toString();
      } else {
        buffer.write(char);
        i++;
      }
    }
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.invalidConditionLiteral,
        _loc(content, offset),
        '字符串字面量缺少结束引号',
      ),
    );
    return null;
  }
  if (_integerPattern.hasMatch(raw)) {
    return int.parse(raw);
  }
  diagnostics.add(
    _diag(
      TemplatePromptErrorCode.invalidConditionLiteral,
      _loc(content, offset),
      '比较值必须是双引号字符串或整数',
    ),
  );
  return null;
}

void _validateCondition(
  _Condition condition,
  Map<String, TemplatePromptVariable> declarationsByName,
  String content,
  List<TemplatePromptDiagnostic> diagnostics,
) {
  final variable = condition.variable;
  final operator = condition.operator;
  final literal = condition.literal;
  if (variable == null || operator == null || literal == null) {
    return;
  }
  final declaration = declarationsByName[variable];
  if (declaration == null) {
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.undefinedConditionVariable,
        _loc(content, condition.offset),
        '条件引用了未声明的变量「$variable」',
      ),
    );
    return;
  }
  final allowedOperators = switch (declaration.type) {
    TemplatePromptVariableType.text => const ['==', '!='],
    TemplatePromptVariableType.select => const ['==', '!='],
    TemplatePromptVariableType.number => const [
      '==',
      '!=',
      '>',
      '>=',
      '<',
      '<=',
    ],
  };
  if (!allowedOperators.contains(operator)) {
    diagnostics.add(
      _diag(
        TemplatePromptErrorCode.invalidConditionOperator,
        _loc(content, condition.offset),
        '变量「$variable」不支持运算符 $operator',
      ),
    );
    return;
  }
  switch (declaration.type) {
    case TemplatePromptVariableType.text:
      if (literal is! String) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidConditionLiteral,
            _loc(content, condition.offset),
            '文本变量只能与双引号字符串比较',
          ),
        );
      }
    case TemplatePromptVariableType.select:
      if (literal is! String || !declaration.options.contains(literal)) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidConditionLiteral,
            _loc(content, condition.offset),
            '比较值必须是声明选项之一',
          ),
        );
      }
    case TemplatePromptVariableType.number:
      if (literal is! int) {
        diagnostics.add(
          _diag(
            TemplatePromptErrorCode.invalidConditionLiteral,
            _loc(content, condition.offset),
            '数字变量只能与整数比较',
          ),
        );
      }
  }
}

// ── 条件块构建 ──────────────────────────────────────────────

class _IfBlock {
  _IfBlock({required this.openOffset});

  final int openOffset;
  final List<_BranchBuilder> branches = [];
  bool sawElse = false;
  List<TemplatePromptNode>? elseNodes;
}

class _BranchBuilder {
  _BranchBuilder({required this.condition});

  final TemplatePromptCondition condition;
  final List<TemplatePromptNode> nodes = [];
}

// ── 诊断与工具 ──────────────────────────────────────────────

TemplatePromptCompilation _inconsistentStoredVariables(String message) {
  return TemplatePromptCompilation(
    program: null,
    diagnostics: [
      TemplatePromptDiagnostic(
        code: TemplatePromptErrorCode.inconsistentStoredVariables,
        location: const TemplatePromptSourceLocation(
          offset: 0,
          line: 1,
          column: 1,
        ),
        message: message,
      ),
    ],
  );
}

TemplatePromptDiagnostic _diag(
  TemplatePromptErrorCode code,
  TemplatePromptSourceLocation location,
  String message,
) {
  return TemplatePromptDiagnostic(
    code: code,
    location: location,
    message: message,
  );
}

/// 把源码 offset 转换为 1 起的行号与列号。
TemplatePromptSourceLocation _loc(String content, int offset) {
  var line = 1;
  var lineStart = 0;
  for (var i = 0; i < offset; i++) {
    if (content.codeUnitAt(i) == 0x0A) {
      line++;
      lineStart = i + 1;
    }
  }
  return TemplatePromptSourceLocation(
    offset: offset,
    line: line,
    column: offset - lineStart + 1,
  );
}

bool _isWhitespaceCodeUnit(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

TemplatePromptComparisonOperator? _operatorFromString(String operator) =>
    switch (operator) {
      '==' => TemplatePromptComparisonOperator.equal,
      '!=' => TemplatePromptComparisonOperator.notEqual,
      '>' => TemplatePromptComparisonOperator.greater,
      '>=' => TemplatePromptComparisonOperator.greaterOrEqual,
      '<' => TemplatePromptComparisonOperator.less,
      '<=' => TemplatePromptComparisonOperator.lessOrEqual,
      _ => null,
    };

bool _stringListEquals(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}
