import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/application/model_catalog_workflow.dart';
import 'package:oh_my_llm/features/settings/data/model_list_client.dart';
import 'package:oh_my_llm/features/settings/domain/models/model_catalog_entry.dart';

void main() {
  test('derives models URL before fetching the catalog', () async {
    String? capturedUrl;
    final workflow = ModelCatalogWorkflow(
      fetchModels: ({required modelsUrl, required apiKey}) async {
        capturedUrl = modelsUrl;
        return const [ModelCatalogEntry(id: 'gpt-4o')];
      },
    );

    final result = await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.example.com/v1/chat/completions',
        apiKey: 'sk-test',
      ),
    );

    expect(capturedUrl, 'https://api.example.com/v1/models');
    expect(result, const [ModelCatalogEntry(id: 'gpt-4o')]);
  });

  test('uses a non-empty override without deriving another URL', () async {
    String? capturedUrl;
    final workflow = ModelCatalogWorkflow(
      fetchModels: ({required modelsUrl, required apiKey}) async {
        capturedUrl = modelsUrl;
        return const [];
      },
    );

    await workflow.fetch(
      const ModelCatalogRequest(
        apiUrl: 'https://api.example.com/v1/chat/completions',
        apiKey: 'sk-test',
        modelsUrlOverride: 'https://gateway.example.com/models',
      ),
    );

    expect(capturedUrl, 'https://gateway.example.com/models');
  });

  test('maps data-client failures to a stable application failure', () async {
    final workflow = ModelCatalogWorkflow(
      fetchModels: ({required modelsUrl, required apiKey}) async {
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
