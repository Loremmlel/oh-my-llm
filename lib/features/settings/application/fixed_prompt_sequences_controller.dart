import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fixed_prompt_sequence_repository.dart';
import '../domain/models/fixed_prompt_sequence.dart';

final fixedPromptSequencesProvider =
    NotifierProvider<FixedPromptSequencesController, List<FixedPromptSequence>>(
      FixedPromptSequencesController.new,
    );

/// 固定顺序提示词控制器，负责序列列表的加载、增删改和排序。
class FixedPromptSequencesController
    extends Notifier<List<FixedPromptSequence>> {
  FixedPromptSequenceRepository get _repository =>
      ref.read(fixedPromptSequenceRepositoryProvider);

  @override
  /// 读取已保存的固定顺序提示词序列并作为初始状态。
  List<FixedPromptSequence> build() {
    return _repository.loadAll();
  }

  /// 新增或更新一个固定顺序提示词序列。
  Future<void> upsert(FixedPromptSequence sequence) async {
    final sequences = [...state];
    final existingIndex = sequences.indexWhere(
      (item) => item.id == sequence.id,
    );

    if (existingIndex == -1) {
      sequences.add(sequence);
    } else {
      sequences[existingIndex] = sequence;
    }

    state = _sort(sequences);
    await _repository.saveAll(state);
  }

  /// 按 id 删除一个固定顺序提示词序列。
  Future<void> deleteById(String id) async {
    state = state
        .where((sequence) => sequence.id != id)
        .toList(growable: false);
    await _repository.saveAll(state);
  }

  /// 按更新时间对序列进行排序。
  List<FixedPromptSequence> _sort(List<FixedPromptSequence> sequences) {
    sequences.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(sequences);
  }
}
