import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prompt_template_repository.dart';
import '../domain/models/prompt_template.dart';

final promptTemplatesProvider =
    NotifierProvider<PromptTemplatesController, List<PromptTemplate>>(
      PromptTemplatesController.new,
    );

/// Prompt 模板控制器，负责模板列表的加载、增删改和排序。
class PromptTemplatesController extends Notifier<List<PromptTemplate>> {
  PromptTemplateRepository get _repository =>
      ref.read(promptTemplateRepositoryProvider);

  @override
  /// 读取已保存的 Prompt 模板并作为初始状态。
  List<PromptTemplate> build() {
    return _repository.loadAll();
  }

  /// 新增或更新一个 Prompt 模板。
  Future<void> upsert(PromptTemplate template) async {
    final templates = [...state];
    final existingIndex = templates.indexWhere(
      (item) => item.id == template.id,
    );

    if (existingIndex == -1) {
      templates.add(template);
    } else {
      templates[existingIndex] = template;
    }

    state = _sort(templates);
    await _repository.saveAll(state);
  }

  /// 按 id 删除一个 Prompt 模板。
  Future<void> deleteById(String id) async {
    state = state
        .where((template) => template.id != id)
        .toList(growable: false);
    await _repository.saveAll(state);
  }

  /// 按更新时间对模板进行排序。
  List<PromptTemplate> _sort(List<PromptTemplate> templates) {
    templates.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(templates);
  }
}
