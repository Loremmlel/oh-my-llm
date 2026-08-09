import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/model_catalog_workflow.dart';
import 'package:oh_my_llm/features/settings/data/model_list_client.dart';
import 'package:oh_my_llm/features/settings/domain/models/model_catalog_entry.dart';

void main() {
  test('derives /v1/models from an API root via the resolver', () async {
    String? capturedUrl;
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({required modelsUrl, required apiKey, required apiProtocol}) async {
            capturedUrl = modelsUrl;
            return const [ModelCatalogEntry(id: 'claude-3-5-sonnet')];
          },
    );

    final result = await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.anthropic.com',
        apiKey: 'sk-test',
        apiProtocol: LlmApiProtocol.anthropic,
      ),
    );

    expect(capturedUrl, 'https://api.anthropic.com/v1/models');
    expect(result, const [ModelCatalogEntry(id: 'claude-3-5-sonnet')]);
  });

  test('strips a known generation suffix before deriving /v1/models', () async {
    String? capturedUrl;
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({required modelsUrl, required apiKey, required apiProtocol}) async {
            capturedUrl = modelsUrl;
            return const [];
          },
    );

    await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.example.com/v1/messages',
        apiKey: 'sk-test',
        apiProtocol: LlmApiProtocol.anthropic,
      ),
    );

    expect(capturedUrl, 'https://api.example.com/v1/models');
  });

  test('uses a non-empty override without deriving another URL', () async {
    String? capturedUrl;
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({required modelsUrl, required apiKey, required apiProtocol}) async {
            capturedUrl = modelsUrl;
            return const [];
          },
    );

    await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.example.com/v1/chat/completions',
        apiKey: 'sk-test',
        apiProtocol: LlmApiProtocol.chatCompletions,
        modelsUrlOverride: 'https://gateway.example.com/models',
      ),
    );

    expect(capturedUrl, 'https://gateway.example.com/models');
  });

  test('passes the request apiProtocol through to the data fetcher', () async {
    LlmApiProtocol? capturedProtocol;
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({required modelsUrl, required apiKey, required apiProtocol}) async {
            capturedProtocol = apiProtocol;
            return const [];
          },
    );

    await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.example.com/v1/chat/completions',
        apiKey: 'sk-test',
        apiProtocol: LlmApiProtocol.responses,
      ),
    );

    expect(capturedProtocol, LlmApiProtocol.responses);
  });

  test('maps data-client failures to a stable application failure', () async {
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({required modelsUrl, required apiKey, required apiProtocol}) async {
            throw const ModelListException(
              '服务器返回错误（401）',
              responseBody: 'invalid key',
            );
          },
    );

    await expectLater(
      workflow.fetch(
        const ModelCatalogRequest(
          apiUrl: 'https://api.example.com/v1/chat/completions',
          apiKey: 'sk-test',
          apiProtocol: LlmApiProtocol.chatCompletions,
        ),
      ),
      throwsA(
        isA<ModelCatalogFailure>()
            .having((failure) => failure.message, 'message', '服务器返回错误（401）')
            .having((failure) => failure.responseBody, 'body', 'invalid key'),
      ),
    );
  });
}
