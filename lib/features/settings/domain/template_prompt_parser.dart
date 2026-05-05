import 'models/template_prompt.dart';

final _templatePromptPlaceholderPattern = RegExp(r'\{\{([^{}]+)\}\}');

/// 返回模板提示词中所有合法占位符的匹配结果。
Iterable<RegExpMatch> matchTemplatePromptPlaceholders(String content) {
  return _templatePromptPlaceholderPattern.allMatches(content);
}

/// 提取模板提示词中的变量名，并按首次出现顺序去重返回。
List<String> extractTemplatePromptVariableNames(String content) {
  final names = <String>[];
  final seen = <String>{};
  for (final match in matchTemplatePromptPlaceholders(content)) {
    final rawName = match.group(1)?.trim() ?? '';
    if (rawName.isEmpty || seen.contains(rawName)) {
      continue;
    }
    seen.add(rawName);
    names.add(rawName);
  }
  return List.unmodifiable(names);
}

/// 根据模板内容重新计算变量列表，并尽量保留同名变量的默认值。
List<TemplatePromptVariable> reconcileTemplatePromptVariables({
  required String content,
  required List<TemplatePromptVariable> existingVariables,
}) {
  final existingByName = <String, TemplatePromptVariable>{
    for (final variable in existingVariables) variable.name: variable,
  };

  return extractTemplatePromptVariableNames(content).map((name) {
    if (name == templatePromptBodyVariableName) {
      return const TemplatePromptVariable(name: templatePromptBodyVariableName);
    }

    return TemplatePromptVariable(
      name: name,
      defaultValue: existingByName[name]?.defaultValue ?? '',
    );
  }).toList(growable: false);
}
