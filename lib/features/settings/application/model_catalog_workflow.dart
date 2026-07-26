import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/model_list_client.dart';
import '../data/model_list_url.dart';
import '../domain/models/model_catalog_entry.dart';

/// 模型目录请求输入。
final class ModelCatalogRequest {
  const ModelCatalogRequest({
    required this.apiUrl,
    required this.apiKey,
    this.modelsUrlOverride,
  });

  final String apiUrl;
  final String apiKey;
  final String? modelsUrlOverride;
}

/// 面向设置 UI 的模型目录失败信息。
final class ModelCatalogFailure implements Exception {
  const ModelCatalogFailure(this.message, {this.responseBody});

  final String message;
  final String? responseBody;

  @override
  String toString() => message;
}

typedef ModelCatalogFetcher =
    Future<List<ModelCatalogEntry>> Function({
      required String modelsUrl,
      required String apiKey,
    });

/// 将 data 层模型列表客户端收敛为设置页稳定的请求和错误契约。
final class ModelCatalogWorkflow {
  const ModelCatalogWorkflow({required ModelCatalogFetcher fetchModels})
    : _fetchModels = fetchModels;

  final ModelCatalogFetcher _fetchModels;

  Future<List<ModelCatalogEntry>> fetch(ModelCatalogRequest request) async {
    try {
      return await _fetchModels(
        modelsUrl: resolveModelsUrl(request),
        apiKey: request.apiKey,
      );
    } on ModelListException catch (error) {
      throw ModelCatalogFailure(
        error.message,
        responseBody: error.responseBody,
      );
    } catch (error) {
      throw ModelCatalogFailure('未知错误：$error');
    }
  }
}

/// 解析模型目录端点，覆盖地址优先于聊天完成端点推导。
String resolveModelsUrl(ModelCatalogRequest request) {
  final override = request.modelsUrlOverride?.trim();
  return override?.isNotEmpty == true
      ? override!
      : deriveModelsUrl(request.apiUrl);
}

final modelCatalogWorkflowProvider = Provider<ModelCatalogWorkflow>((ref) {
  return ModelCatalogWorkflow(
    fetchModels: ref.watch(modelListClientProvider).fetchModels,
  );
});
