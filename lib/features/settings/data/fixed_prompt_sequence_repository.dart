import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/fixed_prompt_sequence.dart';

const String fixedPromptSequencesStorageKey = 'settings.fixed_prompt_sequences';

/// 固定顺序提示词序列的 SharedPreferences 仓库。
final fixedPromptSequenceRepositoryProvider =
    Provider<FixedPromptSequenceRepository>((ref) {
      return FixedPromptSequenceRepository(
        ref.watch(sharedPreferencesProvider),
      );
    });

/// 读取和保存固定顺序提示词序列列表。
class FixedPromptSequenceRepository {
  const FixedPromptSequenceRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 读取全部固定顺序提示词序列。
  List<FixedPromptSequence> loadAll() {
    final rawJson = _sharedPreferences.getString(
      fixedPromptSequencesStorageKey,
    );
    if (rawJson == null || rawJson.isEmpty) {
      return const [];
    }

    return VersionedJsonStorage.decodeObjectList(
      rawJson: rawJson,
      subject: 'fixed prompt sequences',
    ).map(FixedPromptSequence.fromJson).toList(growable: false);
  }

  /// 保存全部固定顺序提示词序列。
  Future<void> saveAll(List<FixedPromptSequence> sequences) async {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: sequences,
      toJson: (sequence) => sequence.toJson(),
    );
    await _sharedPreferences.setString(fixedPromptSequencesStorageKey, rawJson);
  }
}
