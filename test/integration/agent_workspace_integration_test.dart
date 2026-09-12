import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/composition/agent_bindings.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

import '../helpers/fixtures.dart';
import '../helpers/fake_tool_protocol_http_client.dart';

void main() {
  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 通过生产装配执行工具并持久化，重建控制器后继续同一上下文', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final store = SqliteAgentStore(database);
      final preferences = await TestFixtures.seedPreferences(
        database: database,
        models: [
          TestFixtures.model(
            apiProtocol: protocol,
            apiUrl: 'https://example.com',
            modelName: 'test',
          ),
        ],
      );
      final wire = FakeToolProtocolHttpClient(
        protocol,
        toolName: 'write_document',
        arguments: {'name': '正文', 'content': '工具保存的正文', 'expected_revision': 0},
      );
      ProviderContainer createContainer() => ProviderContainer(
        overrides: [
          ...createAgentBindings(),
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
          httpClientProvider.overrideWithValue(
            CustomHeadersHttpClient(wire, const {}),
          ),
          customHeadersMapProvider.overrideWithValue(const {}),
          appNetworkLoggerProvider.overrideWithValue(const NoopNetworkLogger()),
        ],
      );
      final first = createContainer();
      final controller = first.read(agentWorkspaceProvider.notifier);
      controller.createWorkspace();
      controller.configure(modelId: 'model-1');
      controller.setDraft('保存一份正文');
      await controller.send();
      final state = first.read(agentWorkspaceProvider);
      expect(state.error, isEmpty);
      expect(
        state.runs.single.status,
        AgentRunStatus.completed,
        reason: state.runs.single.error,
      );
      expect(store.readDocument(state.workspace!.id, '正文')?.content, '工具保存的正文');
      expect(wire.requests, hasLength(2));
      final bodyKey = protocol == LlmApiProtocol.responses
          ? 'input'
          : 'messages';
      final firstPrefix = wire.requests.first[bodyKey] as List;
      expect(
        (wire.requests.last[bodyKey] as List).take(firstPrefix.length),
        firstPrefix,
      );
      expect(wire.requests.last['tools'], wire.requests.first['tools']);
      first.dispose();
      final second = createContainer();
      addTearDown(second.dispose);
      final restored = second.read(agentWorkspaceProvider.notifier);
      restored.setDraft('继续');
      await restored.send();
      expect(
        second
            .read(agentWorkspaceProvider)
            .runs
            .every((r) => r.status == AgentRunStatus.completed),
        isTrue,
      );
      expect(wire.requests, hasLength(3));
      expect(store.readDocument(state.workspace!.id, '正文')?.revision, 1);
    });
  }
}
