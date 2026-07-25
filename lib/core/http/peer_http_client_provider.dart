import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// LAN peer 信任域 HTTP Client Provider。
///
/// 返回不带自定义 header 注入的纯 [http.Client]。
/// 局域网 peer（sync / media）不应接收外部 LLM 的自定义 Header，
/// 使用此 Provider 获取独立的 HTTP Client 实例。
final peerHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
