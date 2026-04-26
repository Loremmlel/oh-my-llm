import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prompt_template_repository.dart';
import '../domain/models/prompt_template.dart';

final promptTemplatesProvider =
    NotifierProvider<PromptTemplatesController, List<PromptTemplate>>(
      PromptTemplatesController.new,
    );

class PromptTemplatesController extends Notifier<List<PromptTemplate>> {
  PromptTemplateRepository get _repository =>
      ref.read(promptTemplateRepositoryProvider);

  @override
  List<PromptTemplate> build() {
    return _repository.loadAll();
  }

  Future<void> upsert(PromptTemplate template) async {
    final templates = [...state];
    final existingIndex = templates.indexWhere((item) => item.id == template.id);

    if (existingIndex == -1) {
      templates.add(template);
    } else {
      templates[existingIndex] = template;
    }

    state = _sort(templates);
    await _repository.saveAll(state);
  }

  Future<void> deleteById(String id) async {
    state = state.where((template) => template.id != id).toList(growable: false);
    await _repository.saveAll(state);
  }

  List<PromptTemplate> _sort(List<PromptTemplate> templates) {
    templates.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(templates);
  }
}
