import 'models/template_prompt.dart';

final _templatePromptPlaceholderPattern = RegExp(r'\{\{([^{}]+)\}\}');

/// 返回模板提示词中所有合法占位符的匹配结果。
Iterable<RegExpMatch> matchTemplatePromptPlaceholders(String content) {
  return _templatePromptPlaceholderPattern.allMatches(content);
}

/// 从占位符原始文本中解析变量名和类型标记。
///
/// 输入 `"起始:number"` -> `(name: "起始", type: number)`
/// 输入 `"目标语言"` -> `(name: "目标语言", type: text)`
/// 未知类型或空 `:` 后缀均回退为 [TemplatePromptVariableType.text]。
/// 正文变量名本身不携带类型标记，但如果写成 `{{正文:number}}` 也会被解析为
/// number 类型（虽然实际上正文变量始终被特殊处理）。
typedef TemplatePromptVariableSpec = ({
  String name,
  TemplatePromptVariableType type,
});

/// 解析占位符内部文本，提取变量名和类型标记。
TemplatePromptVariableSpec parseVariableSpec(String raw) {
  final trimmed = raw.trim();
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex <= 0) {
    return (name: trimmed, type: TemplatePromptVariableType.text);
  }

  final name = trimmed.substring(0, colonIndex).trim();
  final typeRaw = trimmed.substring(colonIndex + 1).trim();
  return (name: name, type: TemplatePromptVariableType.fromString(typeRaw));
}

/// 提取模板提示词中的变量规格（含类型），按首次出现顺序去重返回。
List<TemplatePromptVariableSpec> extractTemplatePromptVariableSpecs(
  String content,
) {
  final specs = <TemplatePromptVariableSpec>[];
  final seen = <String>{};
  for (final match in matchTemplatePromptPlaceholders(content)) {
    final rawName = match.group(1)?.trim() ?? '';
    if (rawName.isEmpty) continue;
    final spec = parseVariableSpec(rawName);
    if (spec.name.isEmpty || seen.contains(spec.name)) continue;
    seen.add(spec.name);
    specs.add(spec);
  }
  return List.unmodifiable(specs);
}

/// 提取模板提示词中的变量名，并按首次出现顺序去重返回。
List<String> extractTemplatePromptVariableNames(String content) {
  return extractTemplatePromptVariableSpecs(content)
      .map((spec) => spec.name)
      .toList(growable: false);
}

/// 根据模板内容重新计算变量列表，并尽量保留同名变量的默认值和类型。
List<TemplatePromptVariable> reconcileTemplatePromptVariables({
  required String content,
  required List<TemplatePromptVariable> existingVariables,
}) {
  final existingByName = <String, TemplatePromptVariable>{
    for (final variable in existingVariables) variable.name: variable,
  };

  return extractTemplatePromptVariableSpecs(content).map((spec) {
    if (spec.name == templatePromptBodyVariableName) {
      return const TemplatePromptVariable(name: templatePromptBodyVariableName);
    }

    final existing = existingByName[spec.name];
    // 数字类型新变量默认值为 "1"；已有变量保留其默认值
    final defaultValue = existing?.defaultValue ??
        (spec.type == TemplatePromptVariableType.number ? '1' : '');

    return TemplatePromptVariable(
      name: spec.name,
      defaultValue: defaultValue,
      type: spec.type,
    );
  }).toList(growable: false);
}
