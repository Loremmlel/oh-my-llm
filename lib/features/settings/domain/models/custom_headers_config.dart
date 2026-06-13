import 'package:equatable/equatable.dart';

/// 单个自定义 HTTP 请求头键值对。
class CustomHeaderEntry extends Equatable {
  const CustomHeaderEntry({
    required this.key,
    required this.value,
  });

  /// 请求头键名，如 `User-Agent`、`X-Custom` 等。
  final String key;

  /// 请求头键值，由用户自由填写。
  final String value;

  CustomHeaderEntry copyWith({String? key, String? value}) {
    return CustomHeaderEntry(
      key: key ?? this.key,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
    };
  }

  factory CustomHeaderEntry.fromJson(Map<String, dynamic> json) {
    return CustomHeaderEntry(
      key: (json['key'] as String?) ?? '',
      value: (json['value'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [key, value];
}

/// 自定义 HTTP 请求头配置，包含一组键值对规则。
///
/// 序列化为 JSON 并持久化到 SharedPreferences 中。
/// [toHeaderMap] 将列表转为 `Map<String, String>` 供 HTTP Client 使用，
/// 若存在同 key 的多条规则，后出现的会覆盖前者。
class CustomHeadersConfig extends Equatable {
  const CustomHeadersConfig({
    this.headers = const [],
  });

  /// 请求头规则列表，按用户添加顺序排列。
  final List<CustomHeaderEntry> headers;

  /// 转为 HTTP 请求可用的 header map。
  /// 同 key 的多条规则以最后出现者为准。
  Map<String, String> toHeaderMap() {
    final map = <String, String>{};
    for (final entry in headers) {
      final key = entry.key.trim();
      if (key.isNotEmpty) {
        map[key] = entry.value;
      }
    }
    return map;
  }

  CustomHeadersConfig copyWith({List<CustomHeaderEntry>? headers}) {
    return CustomHeadersConfig(
      headers: headers ?? this.headers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'headers': headers.map((e) => e.toJson()).toList(),
    };
  }

  factory CustomHeadersConfig.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as List<dynamic>?;
    final headers = rawHeaders
            ?.map(
              (item) =>
                  CustomHeaderEntry.fromJson(
                    Map<String, dynamic>.from(item as Map<String, dynamic>),
                  ),
            )
            .toList() ??
        const [];
    return CustomHeadersConfig(headers: headers);
  }

  @override
  List<Object?> get props => [headers];
}
