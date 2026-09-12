import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/agent/application/agent_workspace_controller.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';

import 'llm_bindings.dart';

List<dynamic> createAgentBindings() => [
  agentClientProvider.overrideWith((ref) => ref.watch(llmClientProvider)),
  agentStoreProvider.overrideWith(
    (ref) => SqliteAgentStore(ref.watch(appDatabaseProvider)),
  ),
  agentModelsProvider.overrideWith(
    (ref) => [
      for (final model in ref.watch(llmModelConfigsProvider))
        AgentModel(
          id: model.id,
          label: '${model.providerName} / ${model.displayName}',
          target: LlmRequestTarget(
            protocol: model.apiProtocol,
            endpoint: model.apiUrl,
            apiKey: model.apiKey,
            model: model.modelName,
          ),
          options: LlmGenerationOptions(
            maxOutputTokens: 8192,
            responseHeaderTimeout: const Duration(seconds: 60),
            streamIdleTimeout: const Duration(seconds: 60),
            protocolOptions: model.apiProtocol == LlmApiProtocol.anthropic
                ? const MessagesOptions(automaticCacheControl: true)
                : null,
          ),
        ),
    ],
  ),
];
