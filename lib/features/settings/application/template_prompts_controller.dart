import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/template_prompt_repository.dart';
import '../domain/models/template_prompt.dart';

final templatePromptsProvider =
    NotifierProvider<TemplatePromptsController, List<TemplatePrompt>>(
      TemplatePromptsController.new,
    );

/// 模板提示词控制器，负责模板列表的加载、增删改和排序。
class TemplatePromptsController extends Notifier<List<TemplatePrompt>> {
  SqliteTemplatePromptRepository get _repository =>
      ref.read(templatePromptRepositoryProvider);

  @override
  /// 读取已保存的模板提示词并作为初始状态。
  List<TemplatePrompt> build() {
    return _repository.loadAll();
  }

  /// 新增或更新一个模板提示词。
  Future<void> upsert(TemplatePrompt templatePrompt) async {
    final templatePrompts = [...state];
    final existingIndex = templatePrompts.indexWhere(
      (item) => item.id == templatePrompt.id,
    );

    if (existingIndex == -1) {
      templatePrompts.add(templatePrompt);
    } else {
      templatePrompts[existingIndex] = templatePrompt;
    }

    state = _sort(templatePrompts);
    await _repository.saveAll(state);
  }

  /// 批量新增或更新多个模板提示词，一次性刷新状态。
  Future<void> upsertAll(List<TemplatePrompt> templatePrompts) async {
    final updated = [...state];
    for (final templatePrompt in templatePrompts) {
      final index = updated.indexWhere((item) => item.id == templatePrompt.id);
      if (index == -1) {
        updated.add(templatePrompt);
      } else {
        updated[index] = templatePrompt;
      }
    }
    state = _sort(updated);
    await _repository.saveAll(state);
  }

  /// 按 id 删除一个模板提示词。
  Future<void> deleteById(String id) async {
    state = state
        .where((templatePrompt) => templatePrompt.id != id)
        .toList(growable: false);
    await _repository.saveAll(state);
  }

  /// 按更新时间对模板提示词进行排序。
  List<TemplatePrompt> _sort(List<TemplatePrompt> templatePrompts) {
    templatePrompts.sort(
      (left, right) => right.updatedAt.compareTo(left.updatedAt),
    );
    return List.unmodifiable(templatePrompts);
  }
}
