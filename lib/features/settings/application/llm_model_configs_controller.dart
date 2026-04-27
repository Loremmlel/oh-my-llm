import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/llm_model_config_repository.dart';
import '../domain/models/llm_model_config.dart';

final llmModelConfigsProvider =
    NotifierProvider<LlmModelConfigsController, List<LlmModelConfig>>(
      LlmModelConfigsController.new,
    );

/// 模型配置控制器，负责列表加载、增删改和排序。
class LlmModelConfigsController extends Notifier<List<LlmModelConfig>> {
  LlmModelConfigRepository get _repository =>
      ref.read(llmModelConfigRepositoryProvider);

  @override
  /// 读取已保存的模型配置并作为初始状态。
  List<LlmModelConfig> build() {
    return _repository.loadAll();
  }

  /// 新增或更新一个模型配置。
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

  /// 批量新增或更新多个模型配置，一次性刷新状态。
  Future<void> upsertAll(List<LlmModelConfig> configs) async {
    final updated = [...state];
    for (final config in configs) {
      final i = updated.indexWhere((c) => c.id == config.id);
      if (i == -1) {
        updated.add(config);
      } else {
        updated[i] = config;
      }
    }
    state = _sort(updated);
    await _repository.saveAll(state);
  }

  /// 按 id 删除一个模型配置。
  Future<void> deleteById(String id) async {
    state = state.where((config) => config.id != id).toList(growable: false);
    await _repository.saveAll(state);
  }

  /// 按显示名称对模型配置进行排序。
  List<LlmModelConfig> _sort(List<LlmModelConfig> configs) {
    configs.sort((left, right) {
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    });

    return List.unmodifiable(configs);
  }
}
