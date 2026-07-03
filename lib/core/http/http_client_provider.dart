import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'custom_headers_http_client.dart';
import 'custom_headers_provider.dart';

/// 全局 HTTP Client 单例 Provider。
///
/// 返回同一个 [CustomHeadersHttpClient] 实例，不会被重新构建，
/// 避免 mid-flight 请求因 client 重建而中断。
/// 所有需要发起 HTTP 请求的模块都应通过此 provider 获取 client。
final httpClientProvider = Provider<CustomHeadersHttpClient>((ref) {
  final inner = http.Client();
  final client = CustomHeadersHttpClient(inner, {});
  ref.onDispose(client.close);
  return client;
});

/// 同步 Provider：监听 [customHeadersMapProvider] 变化并同步到全局 HTTP Client。
///
/// 非 autoDispose Provider，创建后在整个应用生命周期内保持存活。
/// 在应用根组件 [OhMyLlmApp.build()] 中被 watch 以触发初始创建和持续同步。
final customHeadersSyncProvider = Provider<void>((ref) {
  final headers = ref.watch(customHeadersMapProvider);
  final client = ref.read(httpClientProvider);
  client.updateHeaders(headers);
});
