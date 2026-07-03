import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自定义 HTTP 请求头 Provider（core 层抽象）。
///
/// 返回需要附加到所有出站 HTTP 请求的 header 映射。
/// feature 层在 bootstrap 时 override 为具体的 headers 源。
final customHeadersMapProvider = Provider<Map<String, String>>((ref) {
  throw UnimplementedError(
    'customHeadersMapProvider must be overridden at bootstrap.',
  );
});
