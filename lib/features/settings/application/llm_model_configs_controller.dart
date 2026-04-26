import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/llm_model_config_repository.dart';
import '../domain/models/llm_model_config.dart';

final llmModelConfigsProvider =
    NotifierProvider<LlmModelConfigsController, List<LlmModelConfig>>(
      LlmModelConfigsController.new,
    );

class LlmModelConfigsController extends Notifier<List<LlmModelConfig>> {
  LlmModelConfigRepository get _repository =>
      ref.read(llmModelConfigRepositoryProvider);

  @override
  List<LlmModelConfig> build() {
    return _repository.loadAll();
  }

  Future<void> upsert(LlmModelConfig config) async {
    final configs = [...state];
    final existingIndex = configs.indexWhere((item) => item.id == config.id);

    if (existingIndex == -1) {
      configs.add(config);
    } else {
      configs[existingIndex] = config;
    }

    state = _sort(configs);
    await _repository.saveAll(state);
  }

  Future<void> deleteById(String id) async {
    state = state.where((config) => config.id != id).toList(growable: false);
    await _repository.saveAll(state);
  }

  List<LlmModelConfig> _sort(List<LlmModelConfig> configs) {
    configs.sort((left, right) {
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    });

    return List.unmodifiable(configs);
  }
}
