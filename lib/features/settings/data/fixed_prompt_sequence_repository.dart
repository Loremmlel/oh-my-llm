import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import 'sqlite_fixed_prompt_sequence_repository.dart';

export 'sqlite_fixed_prompt_sequence_repository.dart'
    show
        SqliteFixedPromptSequenceRepository,
        fixedPromptSequenceRepositoryProvider;

/// SharedPreferences 中旧版固定顺序提示词数据的键名，仅供迁移时使用。
const String fixedPromptSequencesStorageKey = 'settings.fixed_prompt_sequences';

/// 旧版 SharedPreferences 固定顺序提示词仓库，仅供一次性数据迁移使用。
///
/// 正式读写请使用 [fixedPromptSequenceRepositoryProvider] 对应的
/// [SqliteFixedPromptSequenceRepository]。
class LegacyFixedPromptSequenceRepository {
  const LegacyFixedPromptSequenceRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 从 SharedPreferences 读取旧版全部固定顺序提示词序列。
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
}

/// 仅供测试使用：通过 SharedPreferences 保存固定顺序提示词序列（用于迁移路径测试）。
///
/// 生产代码不应调用此方法，数据写入应通过 [SqliteFixedPromptSequenceRepository.saveAll]。
@visibleForTesting
Future<void> saveLegacyFixedPromptSequencesForTest(
  SharedPreferences preferences,
  List<FixedPromptSequence> sequences,
) async {
  final rawJson = VersionedJsonStorage.encodeObjectList(
    items: sequences,
    toJson: (s) => s.toJson(),
  );
  await preferences.setString(fixedPromptSequencesStorageKey, rawJson);
}

