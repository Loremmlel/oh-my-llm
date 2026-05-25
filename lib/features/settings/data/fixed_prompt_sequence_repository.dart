import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/legacy_preferences_json_storage.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import 'sqlite_fixed_prompt_sequence_repository.dart';

export 'sqlite_fixed_prompt_sequence_repository.dart'
    show
        fixedPromptSequenceRepository,
        fixedPromptSequenceRepositoryProvider;

/// SharedPreferences 中旧版固定顺序提示词数据的键名，仅供迁移时使用。
const String fixedPromptSequencesStorageKey = 'settings.fixed_prompt_sequences';

/// 旧版 SharedPreferences 固定顺序提示词仓库，仅供一次性数据迁移使用。
///
/// 正式读写请使用 [fixedPromptSequenceRepositoryProvider] 对应的
/// [SqliteEntityRepository]。
class LegacyFixedPromptSequenceRepository {
  const LegacyFixedPromptSequenceRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 从 SharedPreferences 读取旧版全部固定顺序提示词序列。
  List<FixedPromptSequence> loadAll() {
    return loadLegacyPreferenceCollection(
      preferences: _sharedPreferences,
      storageKey: fixedPromptSequencesStorageKey,
      subject: 'fixed prompt sequences',
      fromJson: FixedPromptSequence.fromJson,
    );
  }
}

