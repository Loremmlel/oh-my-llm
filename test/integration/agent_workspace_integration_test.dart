import 'dart:convert';

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
    test('${protocol.name} 通过生产装配保存正文与状态，重建控制器后继续并撤回', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final store = SqliteAgentStore(database);
      const workspaceId = 'script-novel';
      store.saveWorkspace(AgentWorkspace(id: workspaceId, title: '剧本小说'));
      final script = store.writeDocument(
        workspaceId,
        '',
        '---\nname: 秋季来信\ndescription: 秋季相关\n---\n三周后必须面对争议。',
        kind: AgentDocumentKind.script,
      );
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
        script: [
          (name: 'read_script', arguments: {'script_id': script.id}),
          (
            name: 'spawn_subagent',
            arguments: {
              'role': 'writer',
              'task': '撰写正文并审查交付',
              'background': false,
            },
          ),
          (
            name: 'write_document',
            arguments: {'name': '正文', 'content': '工具保存的正文'},
          ),
          (
            name: 'review_document',
            arguments: {'name': '正文', 'task': '核对当前稿件'},
          ),
          (
            name: 'submit_review',
            arguments: {'approved': true, 'feedback': '通过'},
          ),
          (name: 'update_story_state', arguments: {'name': '正文'}),
          (
            name: 'commit_story_state',
            arguments: {
              'operations': [
                {
                  'operation': 'insert',
                  'table': 'scene',
                  'row_id': '',
                  'cells': [
                    {'column': 'place', 'value': '图书馆'},
                  ],
                },
              ],
            },
          ),
        ],
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
      final options = first.read(agentModelsProvider).single.options;
      expect(options.responseHeaderTimeout, const Duration(minutes: 10));
      expect(options.streamIdleTimeout, const Duration(minutes: 10));
      final controller = first.read(agentWorkspaceProvider.notifier);
      controller.configure(modelId: 'model-1');
      controller.setDraft('保存一份正文');
      await controller.send();
      final state = first.read(agentWorkspaceProvider);
      expect(state.error, isEmpty);
      expect(
        state.runs.firstWhere((r) => r.parentId == null).status,
        AgentRunStatus.completed,
        reason: state.runs.firstWhere((r) => r.parentId == null).error,
      );
      expect(store.readDocument(state.workspace!.id, '正文')?.content, '工具保存的正文');
      expect(
        store.readStoryState(state.workspace!.id).rows.single.cells['place'],
        '图书馆',
      );
      expect(wire.requests, hasLength(7));
      expect(jsonEncode(wire.requests.first), isNot(contains('三周后必须面对争议')));
      expect(jsonEncode(wire.requests[1]), contains('三周后必须面对争议'));
      expect(jsonEncode(wire.requests[2]), isNot(contains('三周后必须面对争议')));
      final tokenKey = switch (protocol) {
        LlmApiProtocol.chatCompletions => 'max_completion_tokens',
        LlmApiProtocol.responses => 'max_output_tokens',
        LlmApiProtocol.anthropic => 'max_tokens',
      };
      for (final request in wire.requests) {
        expect(request[tokenKey], greaterThanOrEqualTo(65536));
      }
      final bodyKey = protocol == LlmApiProtocol.responses
          ? 'input'
          : 'messages';
      final firstPrefix = wire.requests[2][bodyKey] as List;
      expect(
        (wire.requests[3][bodyKey] as List).take(firstPrefix.length),
        firstPrefix,
      );
      expect(wire.requests[3]['tools'], wire.requests[2]['tools']);
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
      expect(wire.requests, hasLength(8));
      expect(store.listDocuments(state.workspace!.id), hasLength(2));
      restored.withdrawLatestRound();
      expect(store.readStoryState(state.workspace!.id).rows, isEmpty);
      expect(second.read(agentWorkspaceProvider).workspace!.draft, '保存一份正文');
    });
  }
}
