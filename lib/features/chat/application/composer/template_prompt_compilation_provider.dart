import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';

/// Chat application 唯一的模板编译缓存边界。
///
/// `TemplatePrompt` 不可变且 Equatable，内容、变量、默认值、类型与选项全部
/// 参与 family key 相等，模板更新后自动重新编译；不再维护第二份内容哈希表，
/// 也不把 AST 保留在持久化状态里。
final templatePromptCompilationProvider = Provider.autoDispose
    .family<TemplatePromptCompilation, TemplatePrompt>((ref, prompt) {
      return compileTemplatePromptDefinition(prompt);
    });
