import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sqlite_memory_prompt_repository.dart';
import '../domain/models/memory_prompt.dart';

final memoryPromptsProvider =
    NotifierProvider<MemoryPromptsController, List<MemoryPrompt>>(
      MemoryPromptsController.new,
    );

/// 记忆总结提示词控制器，负责列表的加载、增删改和排序。
class MemoryPromptsController extends Notifier<List<MemoryPrompt>> {
  SqliteMemoryPromptRepository get _repository =>
      ref.read(memoryPromptRepositoryProvider);

  @override
  List<MemoryPrompt> build() {
    return _repository.loadAll();
  }

  Future<void> upsert(MemoryPrompt memoryPrompt) async {
    final updated = [...state];
    final existingIndex = updated.indexWhere((item) => item.id == memoryPrompt.id);
    if (existingIndex == -1) {
      updated.add(memoryPrompt);
    } else {
      updated[existingIndex] = memoryPrompt;
    }
    state = _sort(updated);
    await _repository.saveAll(state);
  }

  Future<void> upsertAll(List<MemoryPrompt> memoryPrompts) async {
    final updated = [...state];
    for (final memoryPrompt in memoryPrompts) {
      final index = updated.indexWhere((item) => item.id == memoryPrompt.id);
      if (index == -1) {
        updated.add(memoryPrompt);
      } else {
        updated[index] = memoryPrompt;
      }
    }
    state = _sort(updated);
    await _repository.saveAll(state);
  }

  Future<void> deleteById(String id) async {
    state = state
        .where((memoryPrompt) => memoryPrompt.id != id)
        .toList(growable: false);
    await _repository.saveAll(state);
  }

  List<MemoryPrompt> _sort(List<MemoryPrompt> memoryPrompts) {
    memoryPrompts.sort(
      (left, right) => right.updatedAt.compareTo(left.updatedAt),
    );
    return List.unmodifiable(memoryPrompts);
  }
}
