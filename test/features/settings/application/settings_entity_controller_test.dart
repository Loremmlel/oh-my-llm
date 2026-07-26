import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';

void main() {
  test('upsert future reports the SQLite commit failure', () async {
    final database = AppDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    final controller = container.read(memoryPromptsProvider.notifier);
    database.close();

    await expectLater(
      controller.upsert(
        MemoryPrompt(
          id: 'memory-1',
          name: '记忆',
          content: '内容',
          updatedAt: DateTime(2026),
        ),
      ),
      throwsA(isA<Object>()),
    );
  });
}
